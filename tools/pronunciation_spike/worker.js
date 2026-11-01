// Loqui Quest — pronunciation-scoring spike worker (Phase 0, throwaway).
// Loads the vendored wav2vec2 IPA (gruut) model via transformers.js 3.x and scores
// a recorded waveform against a target phoneme sequence with greedy CTC decode
// + token-sequence edit distance. Run as a MODULE worker:
//   new Worker('worker.js', { type: 'module' })
//
// Local-path pattern (verified against the vendored 3.8.1 bundle):
//   File resolution is: env.localModelPath + <model id> + '/' + <relative file>,
//   and ONNX weights always resolve inside a nested `onnx/` subfolder:
//     AutoModelForCTC.from_pretrained('model')  ->
//       /extras/pronunciation/model/config.json            (root-level config)
//       /extras/pronunciation/model/vocab.json             (CTC tokenizer vocab)
//       /extras/pronunciation/model/onnx/model_q4f16.onnx  (weights, dtype q4f16)
//   so env.localModelPath='/extras/pronunciation/' + id 'model' covers everything
//   with env.allowRemoteModels=false — zero runtime CDN/API-key access.
//
// ORT wasm binaries are vendored too. The 3.8.1 bundle defaults
// `env.backends.onnx.wasm.wasmPaths` to the jsdelivr CDN dist dir; that setting
// is NOT gated by env.allowRemoteModels (it only affects model files). We set
// wasmPaths to the vendored dir below and ship the exact one file pair the
// bundle can resolve (verified in the bundle: both `wasm` and `webgpu` devices
// use only the jsep variants — no other artifacts exist in the resolve table):
//   /extras/pronunciation/ort-wasm-simd-threaded.jsep.mjs   (44,484 B, jsdelivr @3.8.1, SRI-verified)
//   /extras/pronunciation/ort-wasm-simd-threaded.jsep.wasm  (21,596,019 B, jsdelivr @3.8.1, SRI-verified)
//
// Messages in:  { cmd:'load' }
//               { cmd:'score', audio: ArrayBuffer(Float32Array 16kHz mono), target: string }
// Replies out:  { status:'loaded', ms } / { status:'error', stage, error }
//               { score, phones, ms }  / { stage, error }

import { env, AutoModelForCTC, Tensor } from '/extras/pronunciation/transformers.min.js';

// No CDN ever: everything comes from /extras/pronunciation/ (served by build/serve_https.py).
env.allowLocalModels = true;
env.allowRemoteModels = false;
env.localModelPath = '/extras/pronunciation/';
// Vendored-only ONNX Runtime wasm (see header note). Must be set at module
// top-level, i.e. before the first from_pretrained() call, so ORT never hits
// the CDN — allowRemoteModels=false does not cover wasm resolution.
env.backends.onnx.wasm.wasmPaths = '/extras/pronunciation/';

const MODEL_ID = 'model';
const VOCAB_URL = '/extras/pronunciation/model/vocab.json';
// Sampling rate the model was trained on (see preprocessor_config.json).
const SR = 16000;
// vocab.json is authoritative for greedy CTC: "[PAD]" is the CTC blank, "|" is the word separator.
const BLANK = '[PAD]';
const SEP = '|';
const UNK = '[UNK]';

let session = null;          // loaded Wav2Vec2ForCTC
let idToToken = null;        // vocab id -> token string
let blankId = -1;
let sepId = -1;
let unkId = -1;

function log(kind, msg) {
	console.log(`${kind} ${msg}`);
	self.postMessage({ log: `${kind} ${msg}` });
}

// Try WebGPU first (q4f16 is optimized for it), fall back to WASM.
async function loadModel() {
	const t0 = performance.now();
	const errors = [];
	for (const device of ['webgpu', 'wasm']) {
		try {
			log('✅', `Loading model on device "${device}" (dtype q4f16, local only)...`);
			session = await AutoModelForCTC.from_pretrained(MODEL_ID, { dtype: 'q4f16', device });
			const ms = Math.round(performance.now() - t0);
			log('✅', `Model loaded on ${device} in ${ms} ms`);
			return { status: 'loaded', ms, device };
		} catch (e) {
			errors.push(`${device}: ${e?.message || e}`);
			log('⚠️', `Load on ${device} failed: ${e?.message || e}`);
			session = null;
		}
	}
	throw new Error(errors.join(' | '));
}

async function loadVocab() {
	const t0 = performance.now();
	const resp = await fetch(VOCAB_URL);
	if (!resp.ok) throw new Error(`vocab.json fetch failed: HTTP ${resp.status}`);
	const vocab = await resp.json(); // token -> id
	idToToken = new Array(Object.keys(vocab).length).fill(UNK);
	for (const [token, id] of Object.entries(vocab)) idToToken[id] = token;
	blankId = vocab[BLANK] ?? -1;
	sepId = vocab[SEP] ?? -1;
	unkId = vocab[UNK] ?? -1;
	log('✅', `Vocab loaded (${idToToken.length} tokens) in ${Math.round(performance.now() - t0)} ms`);
}

// Greedy CTC decode: argmax per frame, collapse repeats, drop the blank.
// (t, blank, t) collapses to one t — standard CTC greedy convention.
function ctcDecode(logits) {
	const dims = logits.dims;               // [batch, frames, vocabSize]
	const data = logits.data;               // Float32Array
	const frames = dims[dims.length - 2];
	const vSize = dims[dims.length - 1];
	const base = 0;                          // batch 0 (we always run single clips)
	let prev = -1;
	const ids = [];
	for (let t = 0; t < frames; t++) {
		const row = (base * frames + t) * vSize;
		let best = 0, bestV = -Infinity;
		for (let v = 0; v < vSize; v++) {
			const val = data[row + v];
			if (val > bestV) { bestV = val; best = v; }
		}
		if (best !== prev && best !== blankId) ids.push(best);
		prev = best;
	}
	let out = '';
	// UNK/unknown ids emit a single '_' token instead of the literal "[UNK]"
	// string: a multi-char "[UNK]" would inflate the token-level Levenshtein
	// distance against real vocab tokens arbitrarily (one unknown frame would
	// count like multiple missing phonemes), while '_' matches the "unheard
	// phoneme" semantics with a 1-token penalty.
	for (const id of ids) out += (id === sepId ? ' ' : (id === unkId ? '_' : (idToToken[id] ?? '_')));
	// Collapse the separator into single spaces (model may emit repeated "|").
	return out.replace(/ +/g, ' ').trim();
}

// Per-audio normalization (zero-mean / unit-variance), as Wav2Vec2FeatureExtractor
// would do with do_normalize=true. We bypass the processor and feed raw input_values.
function normalize(pcm) {
	let mean = 0;
	for (let i = 0; i < pcm.length; i++) mean += pcm[i];
	mean /= pcm.length;
	let varSum = 0;
	for (let i = 0; i < pcm.length; i++) { const d = pcm[i] - mean; varSum += d * d; }
	const std = Math.sqrt(varSum / pcm.length) || 1e-7;
	const out = new Float32Array(pcm.length);
	for (let i = 0; i < pcm.length; i++) out[i] = (pcm[i] - mean) / std;
	return out;
}

// Levenshtein distance over space-split token sequences (token-level edit distance).
function seqDistance(a, b) {
	const m = a.length, n = b.length;
	let prev = new Array(n + 1);
	let curr = new Array(n + 1);
	for (let j = 0; j <= n; j++) prev[j] = j;
	for (let i = 1; i <= m; i++) {
		curr[0] = i;
		for (let j = 1; j <= n; j++) {
			const cost = a[i - 1] === b[j - 1] ? 0 : 1;
			curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
		}
		[prev, curr] = [curr, prev];
	}
	return prev[n];
}

// score = round(100 * (1 - dist / max(len1, len2))); empty input guards to 0.
function scoreAgainst(predicted, target) {
	const pred = predicted.split(/\s+/).filter(Boolean);
	const targ = target.split(/\s+/).filter(Boolean);
	if (pred.length === 0 || targ.length === 0) return 0;
	const dist = seqDistance(pred, targ);
	return Math.round(100 * (1 - dist / Math.max(pred.length, targ.length)));
}

async function score(audioBuffer, target) {
	if (!session) throw new Error('model not loaded (send {cmd:"load"} first)');
	// Explicit empty-capture guard: reply cleanly instead of relying on the
	// generic throw path (a zero-length buffer would still infer fine but mean
	// nothing, so the reply would be a misleading score).
	if (((audioBuffer?.byteLength ?? 0) >> 2) === 0) {
		log('⚠️', 'Empty capture received — replying {score:0, error:"empty capture"}');
		return { score: 0, phones: '', ms: 0, error: 'empty capture' };
	}
	const t0 = performance.now();
	const pcm = normalize(new Float32Array(audioBuffer));
	log('ℹ️', `Scoring ${(pcm.length / SR).toFixed(2)}s clip (${pcm.length} samples @16kHz)`);
	const input = new Tensor('float32', pcm, [1, pcm.length]);
	const output = await session({ input_values: input });
	const phones = ctcDecode(output.logits);
	const ms = Math.round(performance.now() - t0);
	log('✅', `Inference+decode in ${ms} ms — phones: "${phones}"`);
	return { score: scoreAgainst(phones, target), phones, ms };
}

self.onmessage = async (event) => {
	const { cmd, audio, target } = event.data || {};
	try {
		if (cmd === 'load') {
			await loadVocab();
			self.postMessage(await loadModel());
		} else if (cmd === 'score') {
			const result = await score(audio, target ?? '');
			self.postMessage(result);
		} else {
			log('⚠️', `Unknown command: ${cmd}`);
		}
	} catch (e) {
		// Never throw unhandled into the page.
		const err = String(e?.message || e);
		log('⚠️', `${cmd ?? '?'} failed: ${err}`);
		if (cmd === 'load') self.postMessage({ status: 'error', stage: 'load', error: err });
		else if (cmd === 'score') self.postMessage({ score: 0, phones: '', ms: 0, stage: 'score', error: err });
	}
};

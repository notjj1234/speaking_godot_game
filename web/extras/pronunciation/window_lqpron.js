// Loqui Quest — window.LQPron facade (Task 9).
// In-browser pronunciation scoring API consumed by GDScript via JavaScriptBridge.
// Exposes: isReady, loaded, beginCapture, abandonCapture, endCaptureAndScore.
// The scoring worker (module worker) is booted by this file; model load is async.

const LQPronWorker = (() => {
  let worker = null;
  let initPromise = null;
  let nextId = 1;
  // request-id -> {resolve, reject} for in-flight score requests. The worker
  // tags every reply with the request id (see worker.js), which is what allows
  // postScore to return the real result instead of `undefined`.
  const pending = new Map();
  function ensureWorker() {
    if (!worker) {
      worker = new Worker('/extras/pronunciation/worker.js', { type: 'module' });
      worker.onmessage = (ev) => {
        const data = ev.data || {};
        if (data.status === 'loaded') {
          window.LQPron.loaded = true;
          window.LQPron.isReady = true;
        } else if (data.status === 'error') {
          window.LQPron.loaded = false;
          window.LQPron.isReady = false;
        } else if (data.status === 'score' || data.status === 'score-error') {
          const p = pending.get(data.id);
          if (p) {
            pending.delete(data.id);
            if (data.status === 'score') p.resolve(data.result);
            else p.reject(new Error(data.error || 'score failed'));
          }
        }
      };
      worker.onerror = (ev) => {
        window.LQPron.loaded = false;
        window.LQPron.isReady = false;
      };
      initPromise = (async () => {
        worker.postMessage({ cmd: 'load' });
        await new Promise((resolve, reject) => {
          const to = setTimeout(() => reject(new Error('worker load timeout')), 60000);
          worker.addEventListener('message', function h(ev) {
            // Only the load RESULT settles readiness — the worker logs
            // progress messages first, and treating the first message as
            // "loaded" marked the scorer ready before the model existed.
            const data = ev.data || {};
            if (data.status !== 'loaded' && data.status !== 'error') return;
            clearTimeout(to);
            worker.removeEventListener('message', h);
            resolve(true);
          });
        });
      })();
    }
    return worker;
  }
  return {
    async start() { if (!initPromise) await ensureWorker(); await initPromise; },
    postScore: (msg) => new Promise((resolve, reject) => {
      if (!worker) { reject(new Error('worker not started')); return; }
      const id = nextId++;
      pending.set(id, { resolve, reject });
      worker.postMessage({ ...msg, id });
      // Leak guard: GDScript also bounds its wait, this just clears our map.
      setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error('score timeout'));
        }
      }, 30000);
    }),
  };
})();

window.LQPron = {
  isReady: false,
  loaded: false,
  _state: 'idle',
  _stream: null,
  _recorder: null,
  _chunks: [],
  _pcm: null,
  _ctx: null,

  async beginCapture() {
    if (this._state !== 'idle') return false;
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    this._stream = stream;
    const ctx = new AudioContext();
    this._ctx = ctx;
    const src = ctx.createMediaStreamSource(stream);
    const rec = new MediaRecorder(src.mediaStream || stream, { mimeType: 'audio/webm' });
    this._recorder = rec;
    this._chunks = [];
    rec.ondataavailable = (e) => { if (e.data && e.data.size > 0) this._chunks.push(e.data); };
    await new Promise((resolve) => {
      rec.onstop = async () => {
        const blob = new Blob(this._chunks, { type: rec.mimeType || 'audio/webm' });
        const buf = await blob.arrayBuffer();
        const ab = new AudioContext();
        const audio = await ab.decodeAudioData(buf);
        const pcm = new Float32Array(audio.length ? audio.getChannelData(0).length : 0);
        // resample to 16k mono is done in worker-side via AudioContext; keep simple: use channel data
        window.LQPron._pcm = audio.getChannelData(0);
        window.LQPron._pcmRate = audio.sampleRate;
        resolve(true);
      };
      rec.start();
    });
    this._state = 'recording';
    return true;
  },

  async abandonCapture() {
    if (this._state === 'recording' && this._recorder) {
      try { this._recorder.stop(); } catch (e) { /* noop */ }
    }
    this._state = 'idle';
    if (this._stream) { try { this._stream.getTracks().forEach(t => t.stop()); } catch (e) {} this._stream = null; }
    this._pcm = null;
    return true;
  },

  async endCaptureAndScore(target) {
    if (this._state !== 'recording') return { ok: false, score: -1, phones: '', ms: -1, error: 'not-recording' };
    const rec = this._recorder;
    if (rec) { try { rec.stop(); } catch (e) {} }
    let result;
    try {
      const blob = new Blob(this._chunks, { type: rec ? (rec.mimeType || 'audio/webm') : 'audio/webm' });
      const buf = await blob.arrayBuffer();
      const ab = new AudioContext();
      const audio = await ab.decodeAudioData(buf);
      const channel = audio.getChannelData(0);
      const pcm = new Float32Array(channel.length);
      // 16kHz mono: take channel 0; resample by simple averaging if needed (keep it simple for spike).
      if (audio.sampleRate !== 16000) {
        // naive linear resample
        const ratio = 16000 / audio.sampleRate;
        const out = new Float32Array(Math.floor(channel.length * ratio));
        for (let i = 0; i < out.length; i++) out[i] = channel[Math.floor(i * (audio.sampleRate / 16000))];
        window.LQPron._pcm = out;
        window.LQPron._pcmRate = 16000;
      } else {
        window.LQPron._pcm = channel;
        window.LQPron._pcmRate = 16000;
      }
      result = await LQPronWorker.postScore({ cmd: 'score', audio: window.LQPron._pcm, target: target });
    } catch (e) {
      // Scoring failed (worker error / timeout): report a clean failure so
      // the GDScript side resets instead of waiting out its 6s bound.
      result = { ok: false, score: -1, phones: '', ms: -1, error: String(e?.message || e) };
    } finally {
      // Always release the mic and drop back to idle, even on the error path —
      // otherwise the facade wedges in 'recording' and the callback never fires.
      this._state = 'idle';
      this._pcm = null;
      if (this._stream) { try { this._stream.getTracks().forEach(t => t.stop()); } catch (e) {} this._stream = null; }
    }
    if (window.LQPronScoreCb) {
      try { window.LQPronScoreCb(result); } catch (e) { /* noop */ }
    }
    return result;
  },
};

// Kick off the worker model load as soon as the module runs. Readiness flags
// are owned by the main onmessage handler (status loaded/error) — never set
// them here, or a failed load gets flipped back to "ready".
LQPronWorker.start().catch((e) => {
  window.LQPron.loaded = false;
  window.LQPron.isReady = false;
});

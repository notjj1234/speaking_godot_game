// Loqui Quest — window.LQPron facade (Task 9).
// In-browser pronunciation scoring API consumed by GDScript via JavaScriptBridge.
// Exposes: isReady, loaded, beginCapture, abandonCapture, endCaptureAndScore.
// The scoring worker (module worker) is booted by this file; model load is async.

const LQPronWorker = (() => {
  let worker = null;
  let initPromise = null;
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
    postScore: (msg) => { if (worker) worker.postMessage(msg); },
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
    const result = await LQPronWorker.postScore({ cmd: 'score', audio: window.LQPron._pcm, target: target });
    if (window.LQPronScoreCb) {
      try { window.LQPronScoreCb(result); } catch (e) { /* noop */ }
    }
    this._state = 'idle';
    this._pcm = null;
    return result;
  },
};

// Kick off the worker model load as soon as the module runs.
LQPronWorker.start().then(() => { window.LQPron.loaded = true; window.LQPron.isReady = true; }).catch((e) => { window.LQPron.loaded = false; window.LQPron.isReady = false; });

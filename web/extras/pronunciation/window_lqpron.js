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

  // State: idle -> starting (awaiting the mic) -> recording -> idle.
  // 'recording' must be set while the recorder runs: endCaptureAndScore only
  // scores in that state, and GDScript waits on its callback.
  async beginCapture() {
    if (this._state !== 'idle') return false;
    this._state = 'starting';
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      if (this._state !== 'starting') {
        // Abandoned while the mic prompt was open: never keep the stream.
        stream.getTracks().forEach(t => t.stop());
        return false;
      }
      this._stream = stream;
      const rec = new MediaRecorder(stream, { mimeType: 'audio/webm' });
      this._recorder = rec;
      this._chunks = [];
      rec.ondataavailable = (e) => { if (e.data && e.data.size > 0) this._chunks.push(e.data); };
      rec.start();
      this._state = 'recording';
      return true;
    } catch (e) {
      console.warn('[LQPron] beginCapture failed:', e);
      this._releaseStream();
      this._state = 'idle';
      return false;
    }
  },

  _releaseStream() {
    if (this._stream) { try { this._stream.getTracks().forEach(t => t.stop()); } catch (e) {} this._stream = null; }
  },

  async abandonCapture() {
    if (this._state === 'recording' && this._recorder) {
      try { this._recorder.stop(); } catch (e) { /* noop */ }
    }
    this._state = 'idle';
    this._releaseStream();
    this._pcm = null;
    return true;
  },

  _reply(result) {
    // GDScript receives JS objects as JavaScriptObject, not Dictionary; a JSON
    // string is the one shape it can read back reliably.
    if (window.LQPronScoreCb) {
      try { window.LQPronScoreCb(JSON.stringify(result)); } catch (e) { console.warn('[LQPron] score callback failed:', e); }
    }
    return result;
  },

  async endCaptureAndScore(target) {
    // Always answer through the callback: GDScript parks a paused challenge
    // until it hears back.
    if (this._state !== 'recording') {
      return this._reply({ ok: false, score: -1, phones: '', ms: -1, error: 'not-recording' });
    }
    const rec = this._recorder;
    let result;
    let ab = null;
    try {
      // The final dataavailable fires before 'stop'; building the blob any
      // earlier gives an empty clip.
      if (rec && rec.state !== 'inactive') {
        await new Promise((resolve) => {
          rec.addEventListener('stop', resolve, { once: true });
          try { rec.stop(); } catch (e) { resolve(); }
        });
      }
      const blob = new Blob(this._chunks, { type: rec ? (rec.mimeType || 'audio/webm') : 'audio/webm' });
      const buf = await blob.arrayBuffer();
      ab = new AudioContext();
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
      this._releaseStream();
      if (ab) { try { ab.close(); } catch (e) {} }
    }
    return this._reply(result);
  },
};

// A hidden or closing page must not keep the mic: Safari shows it as still in use.
// The challenge then scores without the clip (endCaptureAndScore replies
// 'not-recording'), which GDScript already treats as "no phoneme pass".
function releaseCaptureWhenHidden() {
  if (window.LQPron._state === 'idle') return;
  window.LQPron.abandonCapture().catch((e) => console.warn('[LQPron] release on hide failed:', e));
}
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') releaseCaptureWhenHidden();
});
window.addEventListener('pagehide', releaseCaptureWhenHidden);

// Kick off the worker model load as soon as the module runs. Readiness flags
// are owned by the main onmessage handler (status loaded/error) — never set
// them here, or a failed load gets flipped back to "ready".
LQPronWorker.start().catch((e) => {
  window.LQPron.loaded = false;
  window.LQPron.isReady = false;
});

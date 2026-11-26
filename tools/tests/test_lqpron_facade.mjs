// F06/F07 regression for web/extras/pronunciation/window_lqpron.js, run in
// Node with browser stand-ins (no browser needed):
//   node tools/tests/test_lqpron_facade.mjs
// Checks: capture reaches 'recording' while the recorder runs; scoring always
// answers through window.LQPronScoreCb (as JSON text GDScript can parse),
// including when nothing is recording; the mic stream is always released.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = fileURLToPath(new URL('.', import.meta.url));
const source = readFileSync(here + '../../web/extras/pronunciation/window_lqpron.js', 'utf8');

let passes = 0;
let failures = 0;
function check(name, cond, detail = '') {
  if (cond) { passes++; console.log(`PASS ${name}`); }
  else { failures++; console.log(`FAIL ${name}${detail ? ' — ' + detail : ''}`); }
}
const tick = () => new Promise((r) => setTimeout(r, 0));

let tracksStopped = 0;
let micDelayMs = 0;
class FakeWorker {
  constructor() { this.listeners = new Set(); this.onmessage = null; }
  addEventListener(_t, fn) { this.listeners.add(fn); }
  removeEventListener(_t, fn) { this.listeners.delete(fn); }
  emit(data) {
    const ev = { data };
    if (this.onmessage) this.onmessage(ev);
    for (const fn of [...this.listeners]) fn(ev);
  }
  postMessage(msg) {
    if (msg.cmd === 'load') setTimeout(() => this.emit({ status: 'loaded' }), 0);
    if (msg.cmd === 'score') {
      const result = { ok: true, score: 88, phones: 'h ə l oʊ', ms: 5, samples: msg.audio.length };
      setTimeout(() => this.emit({ status: 'score', id: msg.id, result }), 0);
    }
  }
}
class FakeRecorder {
  constructor() { this.state = 'inactive'; this.mimeType = 'audio/webm'; this.stopFns = []; }
  addEventListener(type, fn) { if (type === 'stop') this.stopFns.push(fn); }
  start() { this.state = 'recording'; }
  stop() {
    this.state = 'inactive';
    // Like browsers: the final chunk arrives asynchronously, then 'stop'.
    setTimeout(() => {
      this.ondataavailable({ data: { size: 4 } });
      for (const fn of this.stopFns) fn();
    }, 0);
  }
}
class FakeBlob {
  constructor(parts) { this.parts = parts; }
  async arrayBuffer() { return new ArrayBuffer(this.parts.length); }
}
let decodedBytes = -1;
class FakeAudioContext {
  async decodeAudioData(buf) {
    decodedBytes = buf.byteLength;
    return { sampleRate: 16000, length: 8, getChannelData: () => new Float32Array(8) };
  }
  close() {}
}
const scoreCalls = [];
const sandbox = {
  console,
  setTimeout,
  clearTimeout,
  Worker: FakeWorker,
  MediaRecorder: FakeRecorder,
  Blob: FakeBlob,
  AudioContext: FakeAudioContext,
  navigator: {
    mediaDevices: {
      getUserMedia: () => new Promise((resolve) => setTimeout(() => resolve({
        getTracks: () => [{ stop: () => { tracksStopped++; } }],
      }), micDelayMs)),
    },
  },
};
sandbox.window = sandbox;
sandbox.LQPronScoreCb = (payload) => scoreCalls.push(payload);
vm.createContext(sandbox);
vm.runInContext(source, sandbox);
const pron = sandbox.LQPron;
await tick();

// 1. Scoring with nothing recorded still answers.
let r = await pron.endCaptureAndScore('h ə l oʊ');
check('idle score answers via callback', scoreCalls.length === 1);
check('callback payload is JSON text', typeof scoreCalls[0] === 'string');
check('idle score reports not-recording', JSON.parse(scoreCalls[0]).error === 'not-recording');

// 2. A real capture reaches 'recording' and scores the full clip.
const began = await pron.beginCapture();
check('beginCapture resolves true', began === true);
check("state is 'recording' while the recorder runs", pron._state === 'recording', pron._state);
r = await pron.endCaptureAndScore('h ə l oʊ');
check('score answers via callback', scoreCalls.length === 2);
const payload = JSON.parse(scoreCalls[1]);
check('score payload carries the worker score', payload.score === 88 && payload.ok === true, scoreCalls[1]);
check('clip built after the final chunk', decodedBytes === 1, `decoded parts=${decodedBytes}`);
check('mic stream released after scoring', tracksStopped === 1, `stopped=${tracksStopped}`);
check("state back to 'idle'", pron._state === 'idle');

// 3. Abandoned while the mic prompt is still open: the stream is not kept.
micDelayMs = 20;
const pending = pron.beginCapture();
await pron.abandonCapture();
const lateBegin = await pending;
check('abandon during mic prompt cancels capture', lateBegin === false && pron._state === 'idle');
check('late stream is released', tracksStopped === 2, `stopped=${tracksStopped}`);

console.log(`RESULT passes=${passes} failures=${failures}`);
process.exit(failures ? 1 : 0);

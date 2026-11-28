// Audio/mic/camera focus guard in export/web_shell.html, run in Node with
// browser stand-ins (no browser needed):
//   node tools/tests/test_web_audio_visibility.mjs
// Hidden page (tab switch, app switch, swipe away): every AudioContext the page
// made is suspended, read-aloud speech stops, and every getUserMedia track
// (mic or camera) is disabled. Visible again: only what was running resumes.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const shell = readFileSync(here + '../../export/web_shell.html', 'utf8');

let passes = 0;
let failures = 0;
function check(name, cond, detail = '') {
  if (cond) { passes++; console.log(`PASS ${name}`); }
  else { failures++; console.log(`FAIL ${name}${detail ? ' — ' + detail : ''}`); }
}
const tick = () => new Promise((r) => setTimeout(r, 0));

const m = shell.match(/\/\* LQ_AUDIO_FOCUS_BEGIN \*\/([\s\S]*?)\/\* LQ_AUDIO_FOCUS_END \*\//);
check('focus block present in web_shell.html', !!m);
if (!m) {
  console.log(`RESULT passes=${passes} failures=${failures}`);
  process.exit(1);
}

function makeEnv() {
  class FakeAudioContext {
    constructor(state = 'running') { this.state = state; this.suspends = 0; this.resumes = 0; }
    suspend() { this.suspends++; this.state = 'suspended'; return Promise.resolve(); }
    resume() { this.resumes++; this.state = 'running'; return Promise.resolve(); }
  }
  const handlers = {};
  const on = (target) => (type, fn) => { (handlers[target + ':' + type] ||= []).push(fn); };
  const speech = { speaking: true, paused: 0, cancelled: 0, resumed: 0,
    pause() { this.paused++; }, cancel() { this.cancelled++; }, resume() { this.resumed++; } };
  const makeTrack = (kind, enabled = true) => ({ kind, enabled, readyState: 'live' });
  const mediaDevices = {
    nextTracks: [],
    getUserMedia() {
      const tracks = this.nextTracks;
      return Promise.resolve({ getTracks: () => tracks });
    },
  };
  const win = {
    AudioContext: FakeAudioContext,
    webkitAudioContext: FakeAudioContext,
    speechSynthesis: speech,
    navigator: { mediaDevices },
    addEventListener: on('win'),
  };
  const doc = { visibilityState: 'visible', addEventListener: on('doc') };
  const fire = (key) => (handlers[key] || []).forEach((fn) => fn({}));
  const install = new Function('win', 'doc', m[1] + '\nreturn installAudioFocus(win, doc);');
  install(win, doc);
  return { win, doc, fire, speech, mediaDevices, makeTrack,
    hide() { doc.visibilityState = 'hidden'; fire('doc:visibilitychange'); },
    show() { doc.visibilityState = 'visible'; fire('doc:visibilitychange'); } };
}

{
  const env = makeEnv();
  const a = new env.win.AudioContext();
  const b = new env.win.webkitAudioContext();
  check('contexts are tracked', env.win.LQAudioFocus.contexts.size === 2,
    String(env.win.LQAudioFocus.contexts.size));
  env.hide();
  check('hidden suspends running contexts', a.state === 'suspended' && b.state === 'suspended');
  check('speech synthesis cancelled on hide', env.speech.cancelled === 1);
  env.show();
  check('visible resumes them', a.state === 'running' && b.state === 'running');
  check('speech synthesis resumed on show', env.speech.resumed === 1);
}

{
  const env = makeEnv();
  const ctx = new env.win.AudioContext();
  ctx.state = 'suspended'; // e.g. no user gesture yet
  env.hide();
  env.show();
  check('already-suspended context is not resumed', ctx.resumes === 0, String(ctx.resumes));
}

{
  const env = makeEnv();
  const ctx = new env.win.AudioContext();
  env.fire('win:pagehide');
  check('pagehide suspends', ctx.state === 'suspended');
  env.fire('win:pageshow');
  check('pageshow resumes', ctx.state === 'running');
}

{
  const env = makeEnv();
  const ctx = new env.win.AudioContext();
  env.hide();
  env.hide();
  env.show();
  check('double hide still resumes once', ctx.state === 'running' && ctx.resumes === 1, String(ctx.resumes));
}

{
  const env = makeEnv();
  const mic = env.makeTrack('audio');
  const cam = env.makeTrack('video');
  const off = env.makeTrack('audio', false); // the page had turned it off itself
  env.mediaDevices.nextTracks = [mic, cam, off];
  await env.win.navigator.mediaDevices.getUserMedia({ audio: true, video: true });
  await tick();
  env.hide();
  check('hidden disables mic track', mic.enabled === false);
  check('hidden disables camera track', cam.enabled === false);
  env.show();
  check('visible re-enables mic and camera', mic.enabled === true && cam.enabled === true);
  check('track the page disabled stays disabled', off.enabled === false);
}

{
  const env = makeEnv();
  const ended = env.makeTrack('audio');
  env.mediaDevices.nextTracks = [ended];
  await env.win.navigator.mediaDevices.getUserMedia({ audio: true });
  ended.readyState = 'ended';
  env.hide();
  env.show();
  check('ended tracks are ignored', ended.enabled === true && env.win.LQAudioFocus.tracks.size === 0,
    String(env.win.LQAudioFocus.tracks.size));
}

{
  const env = makeEnv();
  env.speech.speaking = false;
  env.hide();
  check('silent speech not paused', env.speech.paused === 0);
}

console.log(`RESULT passes=${passes} failures=${failures}`);
process.exit(failures ? 1 : 0);

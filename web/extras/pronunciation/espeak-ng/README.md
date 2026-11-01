# espeakng.js (vendored)

Grapheme-to-phoneme (G2P) engine: eSpeak-NG compiled to JS + WASM by Eitan Isaacson.

- Source / provenance: `https://cdn.jsdelivr.net/espeakng.js/latest/` (project: `https://github.com/pettarin/espeakng.js-cdn`, upstream: eSpeak-NG)
- Files: `espeakng.min.js` (API shim), `espeakng.worker.js` (WASM binary), `espeakng.worker.data` (voice/language data)
- **License: GPL-3.0** (eSpeak-NG is GPL-3; these builds inherit it). Full text: https://www.gnu.org/licenses/gpl-3.0.html
- **Status: NOT used by the spike page** (`tools/pronunciation_spike/`). The spike hard-codes its 10 target
  phoneme sequences, so no runtime G2P is needed. Vendored here only because Phase 0 planned it for the
  later game-integration task, which must decide how to satisfy GPL-3.0 licensing before shipping it.

Usage (for a later task, if adopted):

```js
// espeakng.min.js is AMD/global; in a classic worker:
//   importScripts('/extras/pronunciation/espeak-ng/espeakng.min.js');
//   espeakng.set_log_level('none');
//   const ws = espeakng.initialize();   // loads espeakng.worker.js + .data from same dir
//   const ipa = ws.TextToIPA({ text: 'hello', voice: 'en-us', phonout_sep: '' }).ipa;
```

Output is eSpeak-style IPA (~1 layers of detail, e.g. `həˈloʊ`), which still needs mapping to the
gruut token set in `model/vocab.json` (stress marks dropped, `oʊ`→`oʊ`, `ɡ` = U+0261 etc.).

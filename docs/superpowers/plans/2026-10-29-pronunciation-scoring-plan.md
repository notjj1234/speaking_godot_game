# Pronunciation-Scoring Speech Challenges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace transcript-only speech-challenge matching with real phoneme-level pronunciation scoring on web (free in-browser model), add a 3-tries system everywhere, and heal the enemy to full HP when all tries are spent.

**Architecture:** A provider-style `PronunciationScorer` family (`speech_scoring/`) mirrors the existing `SttProvider` pattern. On web, raw mic audio is captured in the HTML shell via `getUserMedia`, scored in a Web Worker running the quantized `onnx-community/wav2vec2-ljspeech-gruut-ONNX` phoneme model (transformers.js, self-hosted), and the 0–100 result crosses back to Godot as JSON over `JavaScriptBridge`. `Enemy` owns the try counter and regen rule; `PlayerHudUI` surfaces tries and score feedback. All platforms share the same try/regen rules; non-web platforms (and any word without phoneme data, or any scorer failure) fall back to transcript matching with a phonetic-key fuzzy matcher — gameplay never depends on the model.

**Tech Stack:** Godot 4.7 GDScript · transformers.js (ONNX Runtime Web, vendored ESM bundle) · wav2vec2-ljspeech-gruut q4f16 (~66 MB) · getUserMedia capture in `export/web_shell.html` · gruut (pip, offline gen) for canonical phonemes · espeak-ng WASM vendored for runtime G2P fallback on unseen Sheets words.

**Spec:** Decisions locked in this session's planning prompt (reproduced verbatim in Global Constraints below) + `AGENTS.md` architecture notes. No separate spec doc exists.

## Global Constraints

- 100% free: no paid APIs, no token servers, no vendor keys, no rate-limited free tiers.
- Model: `onnx-community/wav2vec2-ljspeech-gruut-ONNX`, file `model_q4f16.onnx` (~66 MB), vendored/self-hosted — **no runtime CDN fetches**.
- Scoring pipeline: CTC phoneme recognition → canonical phoneme sequence → phoneme edit-distance → 0–100 score. Initial pass threshold 75, tunable via an exported/config value.
- Tries: **3 failed tries → enemy heals to full HP, challenge ends, game resumes, player re-engages.** Above-threshold score OR transcript match passes.
- Android (and any non-viable platform): existing transcript flow + phonetic-key fuzzy matching (Double Metaphone + Levenshtein, pure GDScript) + same try/regen rules. Do not touch the AAR/plugin chain (`addons/plugins/SpeechToText.gdap`).
- Keep all current web safety behaviors: typed fallback, speak button, silence-never-fails, per-challenge `_connect/_disconnect` hygiene, `begin_challenge_mic`/`end_challenge_mic` pairing.
- New backends live behind provider pattern; no platform `OS.get_name()` special-casing in game code beyond the existing `_is_web()` gates in `enemies/scripts/enemy.gd`.
- Godot 4.7 GDScript; runtime `print` logs use the project's ✅/❌/⚠️ emoji style.
- **No godot binary exists on this machine** — Godot-side verification is user-in-editor; only Python/browser-side steps are runnable here.

## Review Focus

Failure modes the spec implies but no task below can fully test on this machine. Each pinned to its owning task:

1. **Typed fallback submissions must never trigger audio scoring** — typed text has no audio; it must go through the transcript-fuzzy path only. Pinned by Task 5 Step 3 (unit check in `test_phonetic_matcher.gd` covers scorer-path routing).
2. **Word missing from `phonemes.json` (dynamic Sheets word) must never break a challenge** — falls back to transcript-fuzzy acceptance. Pinned by Task 8 Step 3.
3. **Post-regen enemy must not instantly re-enter a challenge** — heal sets full HP; the next hit legitimately starts a new challenge, but the challenge-end resume must not double-fire. Pinned by Task 3 Step 4 (user-in-editor checklist).
4. **Model load failure / first-run cold cache on web** — challenge must proceed via transcript path with a ⚠️ log, not hang the paused game. Pinned by Task 10 Step 4 (spike page + user-in-editor).
5. **Simultaneous `getUserMedia` + Web Speech API capture on iOS Safari** — known conflict risk; if capture fails, score path silently degrades to transcript-fuzzy for that try. Pinned by Task 9 Step 4 (spike page device matrix in user's hands).

---

## File Structure (new)

```
speech_scoring/
  pronunciation_scorer.gd          # class PronunciationScorer (base, provider-style)
  web_pronunciation_scorer.gd      # JSBridge ⇄ window.LQPron scoring backend
  unavailable_pronunciation_scorer.gd
  pronunciation_manager.gd         # autoload "PronunciationManager" (provider selection)
  phonetic_matcher.gd              # static metaphone key + levenshtein + similarity
sentence_data/
  phonemes.json                    # precomputed canonical phonemes for shipped words
  phoneme_normalization.json       # espeak-IPA → gruut-token mapping
tools/
  gen_phonemes.py                  # offline canonical-phoneme generator (gruut via pip)
  pronunciation_spike/             # Phase 0 throwaway ONLY; deleted after Phase 3
    index.html, worker.js          # model quality/latency spike (no Godot)
export/web_shell.html             # modified: recorder + worker bootstrap
build/serve_https.py              # modified: serve vendored extras subtree
web/extras/pronunciation/         # vendored runtime assets (source of truth)
  transformers.min.js, worker.js, model/model_q4f16.onnx, model/{config,vocab...}.json, espeakng.js
```

Vendored assets live in `web/extras/pronunciation/` (committed, survives re-exports) and `build/serve_https.py` additionally serves them at `/extras/pronunciation/…` because `build/web/` is wiped by every Godot re-export. At deployment, copy the same folder next to `index.html` (documented in Task 8).

---

### Task 1 [Phase 0 — Spike]: Standalone pronunciation-scoring page

**Files:**
- Create: `tools/pronunciation_spike/index.html`
- Create: `tools/pronunciation_spike/worker.js`
- Create: `web/extras/pronunciation/` (vendored transformers.js + model — vendoring happens once here so later tasks reuse it)

**Interfaces:**
- Produces: `window.LQPron` JS contract used verbatim by all later tasks: `load(): Promise<{ok:boolean, ms:number}>`, `beginCapture(): Promise<boolean>`, `endCaptureAndScore(targetPhonemes: string): Promise<{score:number, phones:string, ms:number}>` — `targetPhonemes` = space-separated IPA tokens (gruut vocab). Nothing else crosses the bridge.

- [ ] **Step 1: Vendor runtime assets** — download `@huggingface/transformers` ESM bundle (current 3.x), `model_q4f16.onnx`, `config.json`, `vocab.json`, `preprocessor_config.json`, `added_tokens.json`, `special_tokens_map.json`, `tokenizer_config.json` from `onnx-community/wav2vec2-ljspeech-gruut-ONNX`, and espeak-ng WASM build, into `web/extras/pronunciation/`. Verify: files exist; `model_q4f16.onnx` ≈ 66 MB.
- [ ] **Step 2: Write spike page** — plain HTML+JS, no Godot: mic button → `getUserMedia` → ScriptProcessor/AudioWorklet capture → stop → worker runs model → greedy CTC decode → phoneme edit distance vs a hard-coded target (`"h eh l ow"` for "hello") → render score 0–100 + predicted phones. Log per-phase timings with ✅/⚠️ prefixes.
- [ ] **Step 3: Verify locally** — `python3 build/serve_https.py` (modify `build/serve_https.py` in this step to also mount `web/extras/` at `/extras/`), open `https://127.0.0.1:8443/tools/pronunciation_spike/index.html`, accept the self-signed warning, say each of the 10 `DEFAULT_WORDS`.
- [ ] **Step 4: Record results** — append a results table (word, said-correctly score, said-wrongly score, model-load ms, score ms) to `tools/pronunciation_spike/SPIKE-RESULTS.md`. Verdict gates Phase 3: threshold 75 must separate correct vs wrong utterances by a clear margin on desktop Chrome. **This is the user's hands-on checkpoint.**

### Task 2 [Phase 1]: `PhoneticMatcher` — metaphone keys + Levenshtein

**Files:**
- Create: `speech_scoring/phonetic_matcher.gd`
- Test: `tools/tests/test_phonetic_matcher.gd` (editor-runnable SceneTree script — user-side)

**Interfaces:**
- Produces (all `static`): `key(word: String) -> String` (Double-Metaphone-style key, lowercase a-z only), `similarity(a: String, b: String) -> float` (0.0–1.0 normalized Levenshtein), `transcript_contains_fuzzy(haystack: String, target: String, min_similarity: float = 0.72) -> bool` (token-window fuzzy containment; exact `in` match short-circuits first).

- [ ] **Step 1:** Write `average_rapid` → `key()` must equal `avrag rapid`-style behavior parity check per Double Metaphone spec cases shipped in the test file; run: user opens `tools/tests/test_phonetic_matcher.gd` in Godot editor, runs scene, expects all ✅ prints. Expected now: script exists, fails to parse (missing file).
- [ ] **Step 2:** Implement the three static functions (standard published Double Metaphone algorithm, condensed for English).
- [ ] **Step 3:** User runs test scene → all ✅. Commit.

### Task 3 [Phase 1]: Enemy try counter + heal-to-full on 3rd fail

**Files:**
- Modify: `enemies/scripts/enemy.gd` (`_take_damage`, `_start_speech_challenge`, `_on_listening_completed`, `_on_speech_result`, new `_host_challenge_fail()`)

**Interfaces:**
- Consumes: HUD `set_challenge_tries(remaining: int)` (Task 4), `show_score_feedback(score: int, tries_left: int)` (Task 4).
- Produces: `const MAX_CHALLENGE_TRIES := 3`; `var max_hp: int`; `_on_speech_result(success: bool, score: int = -1)`; `_host_challenge_fail()` → on 3rd fail: `hp = max_hp`, `challenge_hurt_box = null`, existing `_resume_game_after_challenge()`, 1.0 s `invulnerable` grace (existing flag), ⚠️ log "Enemy restored to full HP. Challenge lost (3/3 tries)."

- [ ] **Step 1:** Capture `max_hp = hp` in `_ready()`. Initialize `challenge_tries_left = MAX_CHALLENGE_TRIES` in `_start_speech_challenge()`, call `player_hud.set_challenge_tries(challenge_tries_left)`.
- [ ] **Step 2:** Rework the two failure tails: web fail path (line ~343) calls `_register_challenge_attempt(recognized_similarity_score)`; non-web fail path calls `_on_speech_result(false)` which now decoys into `_register_challenge_attempt(-1)`. On each fail: `challenge_tries_left -= 1`; if > 0 → HUD feedback with tries left, re-arm listen + typed fallback exactly as today; if == 0 → `_host_challenge_fail()`.
- [ ] **Step 3:** Success paths (exact match, partial match, above-threshold score, all platforms) unchanged — `_on_speech_result(true)` still destroys.
- [ ] **Step 4:** User-in-editor verification checklist: kill enemy → fail 3× → HP restored + resume + grace invulnerability; success on 1st try unchanged; Android build same rules. Commit.

### Task 4 [Phase 1]: HUD tries indicator + score feedback

**Files:**
- Modify: `gui/player_hud/player_hud.gd` (`show_speech_challenge`, `show_feedback`, `hide_speech_challenge`); the `.tscn` gains: `TriesLabel` under `ChallengeVBox` (created in `_ready()` in code, matching `_create_stt_indicator()` pattern — no scene edit needed)

**Interfaces:**
- Produces: `set_challenge_tries(remaining: int)` (renders "Tries: ♥♥♥" style, grey when hidden), `show_score_feedback(score: int, tries_left: int)` (≥75 → green "Good enough! / score"; 50–74 → yellow "Close! score — try again"; <50 → red "Not quite — try again"); failure message blends into existing `show_feedback(false)` flow instead of replacing it.

- [ ] **Step 1:** Implement both methods using the `_create_stt_indicator()` code-built-control pattern; reset state in `show_speech_challenge()`/`hide_speech_challenge()`.
- [ ] **Step 2:** User-in-editor: challenge shows 3 tries; each fail decrements; regen attempt clears to hidden. Commit.

### Task 5 [Phase 1]: Wire transcript-fuzzy acceptance (all platforms)

**Files:**
- Modify: `enemies/scripts/enemy.gd` (`_on_listening_completed`, `_on_partial_transcript`, `_normalize_web_text` sites)

**Interfaces:**
- Consumes: Task 2 `PhoneticMatcher.transcript_contains_fuzzy`.
- Produces: acceptance = exact normalized containment (existing `_contains_phrase`) OR `transcript_contains_fuzzy(...)` — applied on web partials, web finals, Android finals, and typed-fallback submissions. Typed submissions must skip any audio-scoring route (Review Focus #1).

- [ ] **Step 1:** In `_on_listening_completed`, after exact-match check fails, call fuzzy matcher with >= 0.72 similarity as pass; thread the boolean + similarity into `_register_challenge_attempt(sim)`.
- [ ] **Step 2:** Same rule inside `_on_partial_transcript` web fast-path (`_contains_phrase` → replace with matcher where fuzzy wins).
- [ ] **Step 3:** Verify typed fallback (web, dictation-free) passes/fails purely on string match; no scorer call emitted (log ✅). User-in-editor. Commit.

### Task 6 [Phase 2]: Offline canonical-phoneme pipeline

**Files:**
- Create: `tools/gen_phonemes.py`; Create: `sentence_data/phonemes.json`; Create: `sentence_data/phoneme_normalization.json`

**Interfaces:**
- Produces: `phonemes.json` = `{"<exact challenge text>": "<space-joined gruut-IPA tokens>"}` for every word/sentence in `sentence_data/sentences.txt` + `DEFAULT_WORDS`/`DEFAULT_SENTENCES` (`00_globals/global_word_tracker.gd:20-40`). Generator recomputed and re-run whenever `sentences.txt` changes.

- [ ] **Step 1:** Implement generator: `pip install gruut` (offline dev-time only — never runtime); emit tokens lowercased, stress digits stripped, normalized through `phoneme_normalization.json` (gruut↔espeak symbol differences: `ɑ→a`, `ɹ→r`, `ɾ→t|r` context-free mappings shipped with the file).
- [ ] **Step 2:** Run here: `python3 tools/gen_phonemes.py` → expect ✅ print with counts; JSON parses.
- [ ] **Step 3:** Spot-check 5 entries (hello, water, "I like cats", "Good morning") against gruut output. Commit.

### Task 7 [Phase 2]: `PronunciationScorer` provider family + manager autoload

**Files:**
- Create: `speech_scoring/pronunciation_scorer.gd`, `web_pronunciation_scorer.gd`, `unavailable_pronunciation_scorer.gd`, `pronunciation_manager.gd`
- Modify: `project.godot` autoload section (add `PronunciationManager` after `STTManager`)

**Interfaces:**
- Base (provider pattern, mirrors `speech_to_text/stt_provider.gd`): `func is_available() -> bool`, `func begin_capture() -> bool`, `func end_capture_and_score(target_phonemes: String, on_done: Callable /*Dictionary: {score:int, phones:String, ms:int}*/) -> bool`, `func abandon_capture() -> void`.
- Manager: `func get_scorer() -> PronunciationScorer` (web+spike-passed → `WebPronunciationScorer`, else `Unavailable`), `func phonemes_for(text: String) -> String` (loads `sentence_data/phonemes.json` at `_ready`, to_lower-keyed; empty string when missing — callers must treat empty as "no phoneme data").
- Selection mirrors `STTManager._create_provider()` semantics; Android simply gets `Unavailable` (model path is web-only this phase).

- [ ] **Step 1:** Write base + unavailable variants (unavailable: `is_available()→false`).
- [ ] **Step 2:** Implement manager + autoload registration; lazy JSON load (follow `WordTracker`'s lazy `SheetsManager` resolution precedent).
- [ ] **Step 3:** User-in-editor: boot web build → log prints selected provider; Android unaffected (Unavailable). Commit.

### Task 8 [Phase 2]: Runtime G2P fallback for unseen Sheets words (web worker side)

**Files:**
- Modify: `tools/pronunciation_spike/worker.js` → successor `web/extras/pronunciation/worker.js` (espeak-ng phonemize path)
- Consumes: Task 1 vendored espeakng.js, `sentence_data/phoneme_normalization.json`

**Interfaces:**
- Produces: worker message `{type:"phonemize", text}` → reply `{type:"phonemizeResult", tokens:string}`; GDScript calls it only when `phonemes_for(text) == ""`.

- [ ] **Step 1:** In worker: espeak-ng → raw IPA IPA string → strip stress → map every symbol through normalization table → unknown symbol = drop token, log ⚠️ once per session.
- [ ] **Step 2:** Verify on spike page: type a word NOT in phonemes.json (e.g. "tremendous"), confirm tokens emitted. **User confirms.**
- [ ] **Step 3:** Contract test in worker: word present in JSON → precomputed path identical output (✅). Commit.

### Task 9 [Phase 3]: Shell bootstrap — recorder + worker wiring in `export/web_shell.html`

**Files:**
- Modify: `export/web_shell.html` (add `<script type="module">` bootstrap before engine boot)
- Create: `web/extras/pronunciation/window_lqpron.js` (page-side recorder; moved out of spike logic)

**Interfaces:**
- Produces: `window.LQPron` exactly per Task 1 contract, plus `onLoadFail(reason)` callback exposure. Capture: `getUserMedia` stream held between challenges (no re-prompt), ring-buffer Float32 at 16 kHz mono (AudioWorklet downsample). Worker created as module worker from `/extras/pronunciation/worker.js`; transformers.js imported from vendored bundle with `env.backendsOnnx = wasm; env.allowLocalModels = true; modelPath = "/extras/pronunciation/model/"` — zero CDN fetches (Review Focus #4, warm-cache warning logged ⚠️ on first ~66 MB download).
- Failure contract: every method resolves/rejects without throwing; `load()` failure is terminal but non-fatal to the game (GDScript side degrades, Task 10).

- [ ] **Step 1:** Implement recorder + worker lifecycle + LQPron facade; mirror spike behavior; keep all JS in one module; no minifier, no bundler.
- [ ] **Step 2:** Verify spike-mode without Godot: page-level smoke test served by `serve_https.py` (`?spiketest=1` runs the Task 1 flow through the full shell code path). **User confirms on desktop Chrome.**
- [ ] **Step 3:** iOS Safari + Android Chrome matrix test (same URL). Failure here degrades gracefully, record results. Commit.

### Task 10 [Phase 3]: `WebPronunciationScorer` bridge + Enemy integration

**Files:**
- Modify: `speech_scoring/web_pronunciation_scorer.gd`, `enemies/scripts/enemy.gd` (`_start_speech_challenge`, `_on_listening_completed`, `_register_challenge_attempt`)

**Interfaces:**
- Consumes: `window.LQPron` (Task 9), manager `phonemes_for()` (Task 7), existing `challenge_hurt_box`/`_register_challenge_attempt(sim)` from Task 3.
- Produces: web challenge flow = keep Web Speech API listening (transcripts still drive partials/fallbacks); on each final result, **additionally** end capture → score (async, 1–3 s, game stays paused) → accepted if `similarity-based acceptance` (Task 5) OR `score ≥ threshold 75`.

- [ ] **Step 1:** GDScript bridge: `JavaScriptBridge.get_interface("window")` → callable wiring via `JavaScriptBridge.create_callback` (store refs — GC caution pattern from `speech_to_text/web_stt_provider.gd:4-13`), all payload types JS-safe (strings/numbers only).
- [ ] **Step 2:** Integrate in enemy: on final transcript arrival web-side, if scorer available AND phonemes non-empty → score path; merge verdicts; typed fallback text bypasses scorer (Task 5 rule). `abandon_capture()` on challenge teardown (all paths — success, regen, error).
- [ ] **Step 3:** Threshold wiring: `@export var pronunciation_pass_threshold: int = 75` on `Enemy` (per-instance tuning via inspector later).
- [ ] **Step 4:** User-in-editor full matrix: (a) model loaded → perfect pronunciation of "hello" passes on score alone even when STT transcribes wrongly; (b) sloppy pronunciation <75 → "Close! try again", consumes a try; (c) 3 fails → full HP + resume; (d) cold-cache model load failure mid-challenge → transcript path continues, ⚠️ log, no hang. Commit.

### Task 11 [Phase 4]: Tuning + docs + cleanup

**Files:**
- Modify: `docs/superpowers/plans/2026-10-29-pronunciation-scoring-plan.md` (append "What-shipped" addendum) — optional follow-on README section; Delete: `tools/pronunciation_spike/` (after Task 10 matrix passes)

- [ ] **Step 1:** Playtest tuning session with real speaker variation (user + 1–2 others): record pass thresholds that best match felt fairness; set final default in `Enemy` export.
- [ ] **Step 2:** Delete spike folder; ensure `build/serve_https.py` extras mount documented in README alongside the existing HTTPS run instructions.
- [ ] **Step 3:** Final user-in-editor regression: full loop (win, lose-3-tries, typed fallback, Android build, practice dummy unaffected — `make_practice_dummy()` skips scoring).

## Verification Reality (repeated where steps say "user-in-editor")

Commands runnable **here**: `python3 build/serve_https.py` (after Task 1 `serve_https.py` modification), `python3 tools/gen_phonemes.py`, file/JSON checks, `git` operations. **Everything Godot-side** — running the game, opening `.tscn`s, verifying autoplay behaviors — is manual in the user's editor. Do not invent `godot --headless` invocations.

## Open Questions (answer before implementation)

1. **Mic capture mechanism (Task 9):** plan recommends `getUserMedia` in the shell page with the stream held open across challenges (no re-prompts; cleanest 16 kHz PCM handoff to the worker). The alternative — Godot-side capture (`AudioEffectCapture`) — would force bulk float transport through the bridge and fight iOS quirks; I don't consider it viable, but if you disagree, stop me before Task 9.
2. **`model_q4f16.onnx` (~66 MB) in git:** plan vendors it committed to the repo (local dev simplest). Alternatives: Git LFS or a one-time download script. Default: plain commit.
3. **iOS Safari simultaneous-capture risk:** if the Task 9 matrix test fails on Safari, do we accept transcript-fuzzy-only on iOS for v1 (recommended) — or block scoring on iOS explicitly with a one-line HUD hint?

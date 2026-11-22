# Loqui Quest — Game Design Audit (Functionality + Visuals)

Date: 2026-11-13 · Scope: whole game, prioritizing the speech-challenge core loop
Method: static audit only (no Godot binary on this machine). Every finding cites
`file:line` or an asset path. Items marked **[verify in editor]** need a runtime check.

---

## 1. The game as designed today

**Core loop:** melee an enemy until 0 HP → the whole tree pauses → a speech
challenge card appears (word or sentence picked from pools, banded by horde stage)
→ speak the phrase (STT), type it, or tap Speak → success destroys the enemy,
failure burns one of 3 tries; exhausting tries heals the enemy to full HP
(`enemies/scripts/enemy.gd:313-450`).

**Onboarding arc:** keyboard-only playground → level 01 (slimes, keyboard) →
level 02 (voice-only movement, struggle-unlock arrows after 3 misses) → level 03
(optional mic) → Endless Horde (stage-scaled waves, bonfire upgrades on death)/
(`levels/scripts/level.gd:20-82`, `levels/endless_horde/horde_curve.gd`).

**Content:** 42 phrases total (24 words + 18 sentences; counted in
`sentence_data/sentences.txt`), plus 16 built-in defaults
(`00_globals/global_word_tracker.gd:22-42`). Phoneme data covers only the 16
built-ins (`sentence_data/phonemes.json` — 22 keys).

**Visual language:** warm pixel art (nearest filtering project-wide,
`project.godot:143`) on a single grass tile; UI built entirely from ad-hoc
`StyleBoxFlat` + theme overrides (523 override lines across scenes), with **two
competing palettes**: parchment/cream (pause menu, challenge card, success toast)
and dark-green/gold (title screen, bonfire, voice-command panel, STT plate).

---

## 2. Strengths worth protecting

These are good design decisions — recommendations below should not regress them.

1. **Fail-open by default.** Web challenges can never be lost to silence
   (`speech_to_text/web_stt_provider.gd:205-226`); voice-only level 02 restores
   the keyboard if STT won't start (`touch_controls/Scripts/touch_controls.gd:439-456`);
   3 missed voice commands unlock arrows (`touch_controls.gd:650-656`).
2. **Genuinely staged control teaching** — keyboard → forced voice → optional
   voice → full horde, with banners at each step (`levels/scripts/level.gd:20-82`).
3. **Clean provider architecture** for STT and pronunciation scoring
   (`speech_to_text/stt_provider.gd`, `speech_scoring/pronunciation_scorer.gd`)
   — platform quirks are contained.
4. **TTS↔STT interference handled carefully**: Listen stops capture before
   speaking and re-arms via a token-guarded callback (`gui/player_hud/player_hud.gd:679-727`).
5. **Anti-freeze hardening**: pause-aware timers, bounded waits on the JS
   scoring callback, stun caps, TTS watchdog, ghost-result guard.
6. **Motivating death loop in horde**: death banks gems into permanent upgrades
   and full-heals (`gui/bonfire/bonfire.gd:50-68`) — roguelite-lite, low punishment.
7. **Journal is well-suited to a speech game**: streaks, 7-day charts, learned
   phrases (`gui/progress_journal/progress_journal.gd:220-352`).
8. **Pixel-art discipline**: `default_texture_filter=0` (nearest) project-wide;
   sprites share one outlined, warm-palette style.

---

## 3. Findings — Functionality

### 3.1 Core loop & speech challenge

| # | Finding | Evidence | Why it matters to a player |
|---|---------|----------|-----------------------------|
| F1 | **The core mechanic is never explained.** Level 01 says "Kill them and see what happens" and nothing anywhere tells the player a kill requires *speaking the shown word* | `levels/tutorial_items/tutorial_dialog.gd:17-20` | First-time confusion at the exact moment the game pauses and waits for speech — the worst possible place to confuse someone |
| F2 | **Web pronunciation scoring is dead end-to-end.** `begin_capture()` has zero callers, so the ≥75 phoneme pass is unreachable; and even if called, `endCaptureAndScore` awaits a `postScore` promise that resolves `undefined` and the worker's real score is never forwarded | `speech_scoring/web_pronunciation_scorer.gd:45-52`, `enemies/scripts/enemy.gd:469-470`, `web/extras/pronunciation/window_lqpron.js:117-120` | The advertised near-miss forgiveness never fires; every miss burns a try no matter how close the pronunciation |
| F3 | **Difficulty is length-based, not language-based.** Bands use only word count and character count | `00_globals/global_word_tracker.gd:247-259` | "Good morning" (band 2) can arrive before "orange" (band 1); no phonetic or frequency gradation, so "difficulty" doesn't track actual speaking difficulty |
| F4 | **Substring match passes on both platforms.** Saying the target inside any longer sentence succeeds | `enemies/scripts/enemy.gd:362` | Teaches sloppiness; also contradicts AGENTS.md ("Android exact match") — docs are stale |
| F5 | **Two pass standards coexist without explanation:** 0.72 orthographic Levenshtein ("fuzzy") vs 75/100 phoneme score; the matcher named `PhoneticMatcher` is orthographic — its `key()` is dead code | `enemies/scripts/enemy.gd:363,420`, `speech_scoring/phonetic_matcher.gd:17-35,81-84` | A genuinely good pronunciation with different spelling (accent, STT mishearing) gets no credit while a lazy substring pass does — feels arbitrary |
| F6 | **Challenge failure silently heals the enemy to full HP** — only a `print` in the console, no in-world cue | `enemies/scripts/enemy.gd:442-444` | Confusing "why is it alive again and at full health?" moment right after a frustrating failure |
| F7 | **Pacing: every kill = full game pause + card; beetle = up to 7 consecutive challenges; success unpauses instantly with no beat** | `enemies/scripts/enemy.gd:320`, `enemies/beetle/beetle.tscn:752-756`, `gui/player_hud/player_hud.gd:475` | The marquee enemy is the biggest flow-breaker in the game; kills don't feel rewarding, just interrupting |

### 3.2 Progression, content & controls

| # | Finding | Evidence | Why it matters |
|---|---------|----------|----------------|
| F8 | **The entire death-adaptation system is dead code.** `record_horde_death()` doesn't exist (guarded no-op); `resume_stage`/`stuck_stage`/`short_retry`/`warmup` are never written anywhere | `player/Scripts/player.gd:112-113`, `00_globals/progress_tracker.gd:209-235` | Dying at stage 9 always restarts from Practice; the bonfire's "Continue Stage N" label (`gui/bonfire/bonfire.gd:171-174`) and all anti-frustration scaffolding can never trigger. **[verify in editor]** that this isn't a mid-refactor (progress_tracker.gd is dirty in git) |
| F9 | **Content volume is thin for an "endless" mode:** 42 phrases; stage 10+ draws from only 8 four-word sentences, forever | `sentence_data/sentences.txt` (counted), `levels/endless_horde/horde_curve.gd:75-82` | Heavy repetition within ~15 minutes of horde play |
| F10 | **Phoneme data covers only 16 of 42 phrases** — scoring is silently skipped for the rest | `sentence_data/phonemes.json`, `speech_scoring/pronunciation_manager.gd:36-50` | Even if F2 were fixed, most content would still require exact matches |
| F11 | **Zero stakes outside the horde:** lethal damage anywhere else silently refills HP to full | `player/Scripts/player.gd:117-119` | Right for tutorial, but the playground/01–03 loop has no fail pressure — combat feels weightless; the heal has no feedback, so the HP bar mysteriously refills |
| F12 | **Level 01 is an untaught mode gap:** mic button visible, voice commands work in single-step mode, but no banner explains any of it | `levels/scripts/level.gd:20-26`, `touch_controls/Scripts/touch_controls.gd:173-183,692-697` | Early players can toggle the mic with no instructions and get unpredictable behavior |
| F13 | **Voice-command matching is raw substring** — any utterance containing "stop" halts movement | `touch_controls/Scripts/touch_controls.gd:644-648` | Incidental misfires during normal speech |
| F14 | **Mode logic keyed on scene-name strings** (`"02"`, `"Playground"`, `"EndlessHorde"`); the intended `LevelMetadata` replacement isn't referenced by any scene | `levels/scripts/level.gd:6-12`, `touch_controls/Scripts/touch_controls.gd:164,173-183`, `levels/scripts/level_metadata.gd` | Latent bug: renaming a scene silently changes mic behavior, difficulty scaling, and death rules |
| F15 | **Attack is bound to comma and J** — comma is hostile to AZERTY/non-US layouts | `project.godot:109-113` | Physical-keyboard players on non-US layouts can't attack comfortably |
| F16 | **Horde is a dead-end room** — no exit transition; only death or the pause menu leaves | `levels/endless_horde/endless_horde.tscn` | No "quit a run cleanly" affordance; players may force-kill the app and distrust saves |

### 3.3 Support systems

| # | Finding | Evidence | Why it matters |
|---|---------|----------|----------------|
| F17 | **Settings screen is orphaned.** `show_settings()` has zero callers; no Settings button on title or pause menu. This hides STT language (9 languages), speech difficulty (Easy/Normal/Hard), volume, fullscreen | `gui/settings/settings.gd:84`; buttons absent from `gui/pause_menu/pause_menu.tscn` and `levels/title_screen/title_screen.tscn` | Non-English speakers and players the recognizer fails are stuck; difficulty can't be tuned in-game |
| F18 | **Settings Reset is a no-op** — calls nonexistent `SaveManager.reset_save()` and never clears ProgressTracker | `00_globals/global_settings.gd:177-181` | "Reset" would silently do nothing |
| F19 | **No mic test or level meter anywhere** | absence; priming only at `levels/title_screen/title_screen.gd:468-473` | Players discover a dead mic mid-combat with no diagnostic |
| F20 | **Pause-menu Load has no confirmation** (title screen does) | `gui/pause_menu/pause_menu.gd:296-302` vs `levels/title_screen/title_screen.gd:280-327` | One mis-tap discards the current run |
| F21 | **Autosave is opaque** — a full position/HP checkpoint fires 5s after any spoken word, with no indicator | `00_globals/progress_tracker.gd:20-26,52-59` | Players can't reason about what's saved; manual Save's value is unclear |
| F22 | **Dialog doesn't pause gameplay** — only player movement is blocked; enemies can keep attacking | `gui/dialog_system/scripts/dialog_system.gd` (no pause), `player/Scripts/player.gd:146-147` | Being hit while reading dialog feels unfair. **[verify in editor]** whether any shipped level mixes NPCs and hostiles |
| F23 | **Music: one track (a copyrighted Undertale song), muted by default** | `audio/music_manager.gd:3,13-21`, `00_globals/global_settings.gd:16` | Most players never hear music; zero atmosphere variation across levels; shipping risk |
| F24 | **GameOver screen is dead code** — defeat immediately delegates to Bonfire | `gui/game_over/game_over.gd:22-26` | Maintenance hazard; no distinct "retry" affordance |
| F25 | **Google Sheets URL is still the placeholder** — "live word content" never updates in shipped builds | `google_sheets/sheets_manager.gd:5` | Content freshness roadmap blocked on one string |
| F26 | **Telemetry sends `OS.get_unique_id()` + device name to Sheets** on every spoken word | `00_globals/global_word_tracker.gd:314-330,357-384` | Works, but worth a privacy note/consent line, especially for a speech game aimed at learners |

---

## 4. Findings — Visuals

| # | Finding | Evidence | Why it matters |
|---|---------|----------|----------------|
| V1 | **Two competing UI languages, no Theme resource.** Parchment/cream (pause menu `gui/pause_menu/pause_menu.tscn:49`, challenge card, success toast) vs dark-green/gold (title `levels/title_screen/title_screen.tscn:25-40`, bonfire `gui/bonfire/bonfire.tscn:19-121`, voice-command panel `player_hud.gd:168-176`, STT plate `player_hud.gd:802-807`). 523 theme-override lines across .tscn files; every StyleBox hardcoded | throughout `gui/` | The game looks assembled from two different games; any recolor is a dozen-file hunt |
| V2 | **Missing juice: no hitstop, no screen shake, no hit flash anywhere.** Feedback is limited to damage numbers (rise + fade tween, `gui/damage_number/damage_number.gd:36-39`), knockback (`enemies/scripts/states/enemy_state_stun.gd:32`), stun, and a flat "Got it" toast that fades (`player_hud.gd:459-475`) | grep of `player/Scripts`, `enemies/scripts` for `shake/hitstop/flash/create_tween` | Combat feels soft — landing a hit and winning a spoken challenge (the emotional peak of this game) have almost no physical impact |
| V3 | **Success/failure of the marquee mechanic is visually underplayed.** Success = small toast "Got it" then instant unpause; failure = red text "Not quite. N left." | `player_hud.gd:436-475`, `enemies/scripts/enemy.gd:413` | The moment the game exists for deserves a beat: freeze frame, enemy flash, sound, score reveal |
| V4 | **Score is never shown.** `show_feedback(success, _score)` ignores the score; the success toast hardcodes "Got it" | `player_hud.gd:436,459-464` | No sense of *how well* the player spoke it — kills the learning feedback loop that a pronunciation game needs |
| V5 | **State communication is color-only.** STT indicator = a colored dot (red listening / yellow processing / gray idle); failure feedback is red text | `player_hud.gd:866-905` | Colorblind players and small screens get weak state info; no iconography or motion difference except a pulse |
| V6 | **Environments are sparse.** One grass tile for all ground (`tile_maps/sprites/Grass-01.png`); props sheet nearly empty (one bush, `props/Sprites/Props.png`) | asset inspection | Levels read as flat green fields; nothing to anchor navigation or dress the fiction |
| V7 | **Accessibility vars exist but have no UI and aren't consumed:** `ui_scale`, `reduce_motion`, `color_blind_mode`; font sizes hardcoded 10–18px throughout | `00_globals/global_settings.gd:23-25`; e.g. `gui/progress_journal/progress_journal.gd:159`, `interactables/treasure_chest/treasure_chest.tscn:217` | Small pixel fonts and low-contrast parchment on some plates are hostile to low-vision players |
| V8 | **HUD layout uses magic numbers** — hearts/life sprite centered by code (`mid_x`, offset 8/88/176px for plates, `player_hud.gd:102-113,798-801`) | `player_hud.gd` | Fine at 640×480, but every new element re-solves anchoring; the voice panel is a fixed pixel rect that won't scale with `ui_scale` |

---

## 5. Prioritized recommendation backlog

**Effort: S < ~half day · M ~1-2 days · L > 2 days. Priorities assume web is the primary platform.**

### P0 — hurts players now

| Rec | What | Addresses | Effort |
|-----|------|-----------|--------|
| R1 | **Teach the mechanic before it's needed.** Add one dialog/banner line in level 01 before the first kill: "When an enemy falls, speak the word shown on the card." Consider a scripted first kill with a guaranteed easy word | F1 | S |
| R2 | **Finish or remove the death-adaptation system.** Either implement `record_horde_death()` + stage-resume, or strip the dead "Continue Stage N" copy and warmup/short-retry scaffolding so the game doesn't promise what it can't do | F8 | M |
| R3 | **Fix or formally disable the web pronunciation scorer.** Minimum: wire `begin_capture()`, forward the worker score in `window_lqpron.js`, regenerate `phonemes.json` for all 42 phrases (there's already `tools/gen_phonemes.py`). If that's not this sprint, remove the unreachable ≥75 pass path so behavior matches expectations | F2, F10 | M |
| R4 | **Surface the Settings screen.** Add a Settings button (title + pause menu), wire Reset properly, and add a mic test row | F17, F18, F19 | S–M |
| R5 | **Give challenge resolution a beat and a cue.** Freeze ~0.4s on success with enemy flash/shake + score reveal; on final fail, an explicit "The enemy recovers!" message before unpausing | F6, F7, V3 | M |
| R6 | **Decide what death means outside the horde.** Either add a light consequence (respawn at level entry, drop nothing) or an intentional "practice mode — you can't die here" banner so the heal reads as designed, not broken | F11 | S–M |

### P1 — noticeable polish

| Rec | What | Addresses | Effort |
|-----|------|-----------|--------|
| R7 | **Grow content or gate the endgame.** Expand phrases (100+ is a reasonable target for an "endless" mode), and/or cap horde stages with a victory screen until content grows | F9 | M–L |
| R8 | **Rework matching policy.** Show the score always; replace raw substring with token-aware matching; make fuzzy actually phonetic (use the dead `PhoneticMatcher.key()`) or rename it; align silence behavior across platforms; refresh AGENTS.md to match reality | F4, F5, V4 | M |
| R9 | **Unify the UI into one language.** Create a shared `Theme` + stylebox/font/color constants; migrate the 523 overrides scene by scene, starting with HUD + challenge card | V1, V8 | M–L |
| R10 | **Add combat juice:** hitstop (2–4 frames), tiny screen shake on crit/destroy, white hit flash on enemies, challenge-card pop-in animation. Guard with `reduce_motion` | V2 | M |
| R11 | **Band difficulty by speakability, not length.** Use phoneme count, syllables, or word frequency in `_band_of_phrase` | F3 | S–M |
| R12 | **Voice-command robustness:** match on whole-utterance tokens instead of substring; add a visible "Heard: …" confirmation for movement commands (the label exists, `player_hud.gd:413-423` — confirm it shows) | F13 | S |
| R13 | **Fix level 01's mic-mode gap** (banner or hide the mic toggle there) and **add a horde exit** (return-to-title transition or pause-menu quit button) | F12, F16 | S |
| R14 | **Load confirmation + save indicator** in pause menu | F20, F21 | S |
| R15 | **Dialog safety:** pause enemies during dialog, or give NPC areas a safe radius | F22 | S |
| R16 | **Music:** replace the copyrighted track, add 2–3 level-scoped tracks, unmute by default (or remember the user's choice) | F23 | M |
| R17 | **Move mic-mode/death rules off scene-name strings** onto `LevelMetadata` and reference it from scenes | F14 | M |

### P2 — nice-to-have / hygiene

| Rec | What | Addresses | Effort |
|-----|------|-----------|--------|
| R18 | Accessibility pass: wire `ui_scale` (multiplier on font overrides), `reduce_motion` (gate new juice), high-contrast challenge card variant; add non-color state icons to the STT dot | V5, V7 | M |
| R19 | Journal rewards: small unlocks/cosmetics at streak milestones, so streaks have teeth | — | M |
| R20 | Privacy: replace `OS.get_unique_id()` with a random install UUID; add an opt-out line near the mic consent | F26 | S |
| R21 | Cleanup: delete or archive `coming_soon`, `playground_changed.tscn`, `spawn_area/playground2.tscn`, `*.tmp` files, dead `SpeechMatcher`, `speech_matcher.gd`, dead GameOver path, `STTManager.start_speech_recognition`'s dangling scene path | F24 + dead code | S |
| R22 | Attack key: promote J (or Space) as the primary attack binding in tutorials, keep comma as secondary | F15 | S |
| R23 | Environment dressing pass: a second ground tile variant + a dozen props to break up the single-grass look | V6 | M–L |
| R24 | Sheets: deploy the Apps Script and set the real URL, or remove the feature flag | F25 | S |

---

## 6. Open questions (need in-editor / playtest checks)

1. Android silence behavior: does no-speech burn a try (web doesn't)? — `android_stt_provider.gd:45-50`, `enemy.gd:502-532`
2. Does the same-partial-twice web acceptance fire on STT noise in a quiet room? — `enemy.gd:652-668`
3. Fuzzy threshold feel with real mishearings ("cat"→"cut" = 0.67 fails at 0.72) — threshold may need tuning — `enemy.gd:363`
4. Beetle chain pacing: is 7 back-to-back challenges tolerable with 1s split grace? — `beetle.tscn:752-756`, `enemy.gd:26`
5. Does a voice move in flight survive the challenge pause cleanly? — `player.gd:162-165`
6. Is `progress_tracker.gd` mid-refactor (it's dirty in git)? Affects how R2 should land.
7. Voice-only level 02: does the mic auto-start per browser or does every player hit the retry path? — `touch_controls.gd:665-673`
8. Is the "heard" line visible during movement commands on all platforms?
9. Does any shipped level mix NPCs and hostiles (validates F22 severity)?

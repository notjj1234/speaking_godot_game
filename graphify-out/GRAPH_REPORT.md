# Graph Report - speaking_godot_game  (2026-11-18)

## Corpus Check
- 41 files · ~69,798 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 381 file(s) not represented in the graph (top: .gd 103, .uid 103, .import 71)
- WARNING: 381 of 509 files seen (75%) have no supported extractor and are missing from this graph entirely. It may look complete while representing only part of the codebase.

## Summary
- 1995 nodes · 4367 edges · 142 communities (76 shown, 66 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 199 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3b3b5035`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- espeakng.worker.js
- _
- ort-wasm-simd-threaded.jsep.mjs
- ht
- hc
- me
- _i
- evaluate
- _o
- ue
- hi
- i
- ki
- ve
- se
- Q
- _e
- yn
- ae
- LoquiSpeech
- de
- h
- cd
- ml
- paint_enemies.py
- o
- it
- SpeechToTextPlugin.kt
- g
- _r
- .push
- V
- pronunciation_spike/worker.js
- F
- l
- File Structure (new)
- _t
- M
- gen_phonemes.py
- AGENTS.md
- initialize
- d
- uf
- _a
- f
- u
- b
- ho
- .tokenizer
- dl
- B
- Nc
- s
- MIDDLE ZONE — Execution Logic, Tool Routing, Diagnostics
- c
- v
- callRuntimeCallbacks
- godotgame/BluetoothPlugin.java
- pr
- cu
- Dn
- k
- pe
- md
- demangle
- lo
- va
- fo
- README.md
- Pronunciation spike — results (Phase 0 gate)
- declareVariable
- ca
- pd
- ensureValid
- to
- X
- _u
- PALETTE.md
- ._call
- Te
- y
- lg
- build_xcframework.sh
- runWithFS
- sd
- ja
- tr
- gu
- la
- Loqui Quest — Game Design Audit (Functionality + Visuals)
- espeakng.min.js
- Be
- De
- ii
- N
- Ge
- id
- kl
- ro
- lt
- jc
- ru
- processData
- aa
- oi
- rs
- ws
- ga
- ha
- fi
- ps
- os
- ni
- bi
- NonNull.java
- espeak-ng/README.md
- additionalImplementations
- processTerm
- gd
- bt
- createInferenceSessionHandler
- rl
- en
- fs
- mi
- au
- lookupVariable
- normalizeAxes
- pi
- qa
- Sn
- vn
- nt
- fc

## God Nodes (most connected - your core abstractions)
1. `_` - 609 edges
2. `se` - 165 edges
3. `i()` - 67 edges
4. `_i` - 59 edges
5. `ve` - 56 edges
6. `ab()` - 55 edges
7. `Nc` - 48 edges
8. `h` - 43 edges
9. `l` - 41 edges
10. `N()` - 38 edges

## Surprising Connections (you probably didn't know these)
- `3.1 Core loop & speech challenge` --references--> `endCaptureAndScore()`  [INFERRED]
  docs/superpowers/specs/2026-11-13-design-audit.md → web/extras/pronunciation/window_lqpron.js
- `constructor()` --indirect_call--> `Xa()`  [INFERRED]
  web/extras/pronunciation/transformers.min.js → web/extras/pronunciation/espeak-ng/espeakng.worker.js
- `ab()` --indirect_call--> `bb()`  [INFERRED]
  web/extras/pronunciation/ort-wasm-simd-threaded.jsep.mjs → web/extras/pronunciation/espeak-ng/espeakng.worker.js
- `vi()` --indirect_call--> `N()`  [INFERRED]
  web/extras/pronunciation/espeak-ng/espeakng.worker.js → web/extras/pronunciation/transformers.min.js
- `yi()` --indirect_call--> `r()`  [INFERRED]
  web/extras/pronunciation/espeak-ng/espeakng.worker.js → web/extras/pronunciation/transformers.min.js

## Import Cycles
- None detected.

## Communities (142 total, 66 thin omitted)

### Community 0 - "espeakng.worker.js"
Cohesion: 0.02
Nodes (39): _abort(), abortOnCannotGrowMemory(), allocate(), assert(), ___buildEnvironment(), castObject(), _clock_gettime(), demangleAll() (+31 more)

### Community 1 - "_"
Cohesion: 0.02
Nodes (47): _, Ac, Bn, __bool__(), cc, Cn, Do, Ec (+39 more)

### Community 2 - "ort-wasm-simd-threaded.jsep.mjs"
Cohesion: 0.05
Nodes (79): tb(), a(), ab(), ac(), $b(), Bb(), bc(), bd() (+71 more)

### Community 3 - "ht"
Cohesion: 0.05
Nodes (38): byteLength(), captureBegin(), captureEnd(), computeKernel(), create(), createTemporaryTensor(), destroy(), download() (+30 more)

### Community 4 - "hc"
Cohesion: 0.09
Nodes (56): ac(), ad(), ae(), bd(), be(), ce(), cj(), _d() (+48 more)

### Community 5 - "me"
Cohesion: 0.11
Nodes (22): ag(), bc(), cf(), eg(), ii(), je(), ji(), ke() (+14 more)

### Community 7 - "evaluate"
Cohesion: 0.15
Nodes (29): applyFilter(), ce(), evalProgram(), evaluate(), evaluateArguments(), evaluateBinaryExpression(), evaluateBlock(), evaluateCallExpression() (+21 more)

### Community 9 - "ue"
Cohesion: 0.09
Nodes (32): ab(), af(), _b(), bf(), dd(), df(), _e(), ec() (+24 more)

### Community 10 - "hi"
Cohesion: 0.09
Nodes (31): ai(), ak(), bb(), bi(), bj(), cb(), ck(), eb() (+23 more)

### Community 12 - "ki"
Cohesion: 0.12
Nodes (29): ah(), aj(), bg(), bh(), bk(), cc(), cg(), ch() (+21 more)

### Community 13 - "ve"
Cohesion: 0.11
Nodes (14): at, be(), constructor(), dt(), It(), Lt(), Me(), Nt() (+6 more)

### Community 14 - "se"
Cohesion: 0.09
Nodes (24): ci, co, cs, ds, ed, ei, es, In (+16 more)

### Community 15 - "Q"
Cohesion: 0.15
Nodes (5): Q, Qn, ra, sa, xn

### Community 16 - "_e"
Cohesion: 0.15
Nodes (9): _e(), fe(), G(), ge(), H(), me, q(), W (+1 more)

### Community 17 - "yn"
Cohesion: 0.22
Nodes (9): Jn, kn(), Kn, Mn, Tn(), Vn(), Wn, Xn() (+1 more)

### Community 18 - "ae"
Cohesion: 0.08
Nodes (10): ae, bc, Fn, gc, hc, Mt, Rc, uc (+2 more)

### Community 19 - "LoquiSpeech"
Cohesion: 0.09
Nodes (5): LoquiSpeech, _language, _listening, _session, LoquiSpeechSession

### Community 20 - "de"
Cohesion: 0.15
Nodes (15): de(), ee(), Ie(), ie, je(), le(), Le, Oe() (+7 more)

### Community 22 - "cd"
Cohesion: 0.11
Nodes (31): _c(), cd(), dc(), hc(), hi(), _i(), id(), ih() (+23 more)

### Community 23 - "ml"
Cohesion: 0.22
Nodes (6): bl, gl, hl, ml, wl, yl

### Community 24 - "paint_enemies.py"
Cohesion: 0.11
Nodes (32): audit(), blank_cell(), build_enemy(), process(), clear_goblin_spear(), clear_rect(), copy_cell(), draw_bandit_hood_down() (+24 more)

### Community 26 - "it"
Cohesion: 0.08
Nodes (30): an, bn(), build(), cn(), createMLContext(), dn(), En(), fetchModelAndCopyToWasmMemory() (+22 more)

### Community 29 - "_r"
Cohesion: 0.08
Nodes (6): _c, $e, gr, Ne, p(), _r

### Community 31 - "V"
Cohesion: 0.31
Nodes (21): D(), V(), a(), c(), d(), G(), H(), i() (+13 more)

### Community 32 - "pronunciation_spike/worker.js"
Cohesion: 0.19
Nodes (16): ctcDecode(), loadModel(), loadVocab(), log(), normalize(), score(), scoreAgainst(), seqDistance() (+8 more)

### Community 33 - "F"
Cohesion: 0.18
Nodes (3): F, m(), toDataURL()

### Community 35 - "File Structure (new)"
Cohesion: 0.11
Nodes (17): File Structure (new), Global Constraints, Open Questions (answer before implementation), Pronunciation-Scoring Speech Challenges Implementation Plan, Review Focus, Task 10 [Phase 3]: `WebPronunciationScorer` bridge + Enemy integration, Task 11 [Phase 4]: Tuning + docs + cleanup, Task 1 [Phase 0 — Spike]: Standalone pronunciation-scoring page (+9 more)

### Community 36 - "_t"
Cohesion: 0.06
Nodes (31): Bt(), compute(), createDownloader(), createMLTensorDownloader(), ct(), Ct, Dt, et (+23 more)

### Community 38 - "gen_phonemes.py"
Cohesion: 0.13
Nodes (6): main(), main(), _phones(), check(), main(), read()

### Community 39 - "AGENTS.md"
Cohesion: 0.13
Nodes (13): Android build specifics, Autoloads (singletons) — registered in `project.godot`, Combat & speech-challenge flow, Export plugin & committed artifacts, Google Sheets integration, Level / travel system, Mic-only voice command mode, Other quirks (+5 more)

### Community 40 - "initialize"
Cohesion: 0.15
Nodes (10): initialize(), kd, nd, onRunStart(), pt, qt, rd, setQueryType() (+2 more)

### Community 42 - "uf"
Cohesion: 0.21
Nodes (13): jc(), mc(), nc(), oc(), oh(), pc(), rf(), sf() (+5 more)

### Community 44 - "f"
Cohesion: 0.20
Nodes (5): f(), i(), fromGpuBuffer(), r(), w()

### Community 47 - "ho"
Cohesion: 0.25
Nodes (5): bo, ho, mo, xo, yo

### Community 48 - ".tokenizer"
Cohesion: 0.13
Nodes (5): cl, _n, qc, tl, zi

### Community 49 - "dl"
Cohesion: 0.17
Nodes (9): al, dl, il, ll, ol, pl, sl, ul (+1 more)

### Community 50 - "B"
Cohesion: 0.14
Nodes (5): he, j(), L(), R(), z

### Community 52 - "s"
Cohesion: 0.12
Nodes (4): ic, lc, run(), s

### Community 53 - "MIDDLE ZONE — Execution Logic, Tool Routing, Diagnostics"
Cohesion: 0.15
Nodes (12): Agentic Output Warning, Credential Safety, Diagnostic Checklist, Input Sanitization -- Pasted Prompts, Intent Extraction, Memory Block, MIDDLE ZONE — Execution Logic, Tool Routing, Diagnostics, PRIMACY ZONE — Identity, Hard Rules, Output Lock (+4 more)

### Community 54 - "c"
Cohesion: 0.25
Nodes (3): c(), P, reshape()

### Community 57 - "callRuntimeCallbacks"
Cohesion: 0.21
Nodes (12): addOnPostRun(), addOnPreRun(), callRuntimeCallbacks(), ensureInitRuntime(), __exit(), exitRuntime(), ExitStatus(), postRun() (+4 more)

### Community 59 - "pr"
Cohesion: 0.09
Nodes (16): ar, br, cr, dr, Er, ir, kr, lr (+8 more)

### Community 60 - "cu"
Cohesion: 0.18
Nodes (5): cu, fu, hu, mu, pu

### Community 64 - "md"
Cohesion: 0.25
Nodes (5): fd, hd, md, xd, yd

### Community 65 - "demangle"
Cohesion: 0.18
Nodes (11): demangle(), ensureString(), _getenv(), getValue(), intArrayFromString(), LazyUint8Array(), lengthBytesUTF8(), Pointer_stringify() (+3 more)

### Community 66 - "lo"
Cohesion: 0.20
Nodes (6): ao, io, lo, oo, so, uo

### Community 67 - "va"
Cohesion: 0.29
Nodes (5): ea, ka, na, ta, va

### Community 68 - "fo"
Cohesion: 0.50
Nodes (3): fo, go, wo

### Community 69 - "README.md"
Cohesion: 0.33
Nodes (5): 📖 About The Project, Acknowledgements, 🚧 Built With, Contact, ⚙️ Getting Started

### Community 70 - "Pronunciation spike — results (Phase 0 gate)"
Cohesion: 0.33
Nodes (5): Correct vs wrong scores, How to run, Pronunciation spike — results (Phase 0 gate), Timings, Verdict

### Community 71 - "declareVariable"
Cohesion: 0.33
Nodes (6): appendVariableUniforms(), declareVariable(), declareVariables(), registerInternalVariable(), registerInternalVariables(), set()

### Community 72 - "ca"
Cohesion: 0.33
Nodes (5): ca, ma, pa, xa, ya

### Community 74 - "ensureValid"
Cohesion: 0.33
Nodes (6): data(), ensureValid(), getData(), gpuBuffer(), mlTensor(), texture()

### Community 75 - "to"
Cohesion: 0.50
Nodes (4): ko, no, to, vo

### Community 80 - "Te"
Cohesion: 0.28
Nodes (4): Ce, ke(), Pe(), Te

### Community 82 - "lg"
Cohesion: 0.57
Nodes (7): hg(), ig(), jg(), kg(), lg(), mg(), ng()

### Community 83 - "build_xcframework.sh"
Cohesion: 0.60
Nodes (4): compile_one(), generate_headers(), PATH, build_xcframework.sh script

### Community 84 - "runWithFS"
Cohesion: 0.50
Nodes (4): finish(), runWithFS(), assert(), processPackageData()

### Community 85 - "sd"
Cohesion: 0.40
Nodes (3): ad, od, sd

### Community 87 - "tr"
Cohesion: 0.25
Nodes (7): jr, nr(), rr(), tr(), vr, xr, Zn

### Community 88 - "gu"
Cohesion: 0.40
Nodes (3): bu, gu, yu

### Community 89 - "la"
Cohesion: 0.40
Nodes (3): da, la, ua

### Community 90 - "Loqui Quest — Game Design Audit (Functionality + Visuals)"
Cohesion: 0.11
Nodes (15): 1. The game as designed today, 2. Strengths worth protecting, 3.1 Core loop & speech challenge, 3.2 Progression, content & controls, 3.3 Support systems, 3. Findings — Functionality, 4. Findings — Visuals, 5. Prioritized recommendation backlog (+7 more)

### Community 94 - "ii"
Cohesion: 0.50
Nodes (3): di, ii, li

### Community 95 - "N"
Cohesion: 0.10
Nodes (8): er(), iu, jl, lu, N(), ou, wd, wu

### Community 97 - "id"
Cohesion: 0.29
Nodes (4): dd, id, ld, ud

### Community 102 - "ru"
Cohesion: 0.50
Nodes (3): nu, ru, su

### Community 103 - "processData"
Cohesion: 1.00
Nodes (3): processData(), finish(), removeRunDependency()

### Community 104 - "aa"
Cohesion: 0.67
Nodes (3): aa, ia, oa

### Community 107 - "rs"
Cohesion: 0.67
Nodes (3): as, rs, ss

### Community 108 - "ws"
Cohesion: 0.67
Nodes (3): bs, ws, ys

### Community 109 - "ga"
Cohesion: 0.67
Nodes (3): ba, ga, wa

### Community 112 - "ps"
Cohesion: 0.67
Nodes (3): hs, ms, ps

### Community 114 - "os"
Cohesion: 0.67
Nodes (3): is, ls, os

### Community 117 - "bi"
Cohesion: 0.17
Nodes (5): bi, ji, vi, wi, yi

### Community 132 - "au"
Cohesion: 0.40
Nodes (3): au, du, uu

## Knowledge Gaps
- **4 isolated node(s):** `_language`, `_listening`, `_session`, `PATH`
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 612 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **66 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_` connect `_` to `ht`, `hc`, `_i`, `evaluate`, `_o`, `i`, `ve`, `se`, `Q`, `_e`, `yn`, `ae`, `de`, `h`, `ml`, `o`, `it`, `g`, `_r`, `.push`, `V`, `F`, `l`, `_t`, `M`, `initialize`, `d`, `_a`, `f`, `u`, `b`, `ho`, `.tokenizer`, `dl`, `B`, `Nc`, `s`, `c`, `v`, `pr`, `cu`, `Dn`, `k`, `pe`, `md`, `lo`, `va`, `fo`, `declareVariable`, `ca`, `pd`, `ensureValid`, `to`, `X`, `_u`, `._call`, `Te`, `y`, `sd`, `ja`, `tr`, `gu`, `la`, `Be`, `De`, `ii`, `N`, `Ge`, `id`, `kl`, `ro`, `lt`, `jc`, `ru`, `aa`, `.bpe`, `oi`, `rs`, `ws`, `ga`, `ha`, `fi`, `ps`, `os`, `ni`, `bi`, `additionalImplementations`, `processTerm`, `gd`, `bt`, `createInferenceSessionHandler`, `rl`, `en`, `fs`, `mi`, `au`, `lookupVariable`, `normalizeAxes`, `pi`, `qa`, `Sn`, `vn`, `nt`, `fc`?**
  _High betweenness centrality (0.571) - this node is a cross-community bridge._
- **What connects `_language`, `_listening`, `_session` to the rest of the system?**
  _4 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `espeakng.worker.js` be split into smaller, more focused modules?**
  _Cohesion score 0.01698132054739786 - nodes in this community are weakly interconnected._
- **Why does `N()` connect `N` to `_`, `F`, `hc`, `pd`, `hi`, `f`, `Q`, `_e`, `B`, `bi`, `cd`, `tr`, `.generate`, `it`, `pr`, `cu`, `V`?**
  _High betweenness centrality (0.080) - this node is a cross-community bridge._
- **Should `_` be split into smaller, more focused modules?**
  _Cohesion score 0.016666666666666666 - nodes in this community are weakly interconnected._
- **Why does `Y()` connect `evaluate` to `_`, `ort-wasm-simd-threaded.jsep.mjs`, `hc`, `X`, `f`, `_e`, `c`, `_r`, `V`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **Should `ort-wasm-simd-threaded.jsep.mjs` be split into smaller, more focused modules?**
  _Cohesion score 0.05343320848938826 - nodes in this community are weakly interconnected._
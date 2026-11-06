# Graph Report - speaking_godot_game  (2026-11-04)

## Corpus Check
- 38 files · ~62,598 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 373 file(s) not represented in the graph (top: .gd 102, .uid 102, .import 68)

## Summary
- 1932 nodes · 4237 edges · 147 communities (80 shown, 67 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 199 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `01434e8f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- espeakng.worker.js
- _
- ort-wasm-simd-threaded.jsep.mjs
- ht
- hc
- _f
- _i
- evaluate
- _o
- ue
- hi
- i
- ki
- ve
- se
- R
- _e
- yn
- ae
- LoquiSpeech
- de
- h
- cd
- ml
- ee
- o
- nn
- SpeechToTextPlugin.kt
- p
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
- N
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
- td
- k
- Rc
- md
- demangle
- lo
- va
- iu
- README.md
- Pronunciation spike — results (Phase 0 gate)
- declareVariable
- ca
- pd
- ensureValid
- Dn
- .fromConfig
- g
- Ft
- ._call
- Te
- y
- Q
- build_xcframework.sh
- runWithFS
- sd
- he
- tr
- gu
- la
- window_lqpron.js
- espeakng.min.js
- Be
- De
- ii
- W
- Ge
- id
- bo
- gt
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
- ji
- ni
- bi
- NonNull.java
- espeak-ng/README.md
- additionalImplementations
- processTerm
- gd
- bt
- ds
- createInferenceSessionHandler
- rl
- ja
- en
- fetchModelAndCopyToWasmMemory
- fs
- mi
- jt
- kl
- lookupVariable
- normalizeAxes
- pi
- qa
- rd
- Sn
- vn
- xa

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
- `State machines (player & enemy)` --references--> `init()`  [INFERRED]
  AGENTS.md → web/extras/pronunciation/transformers.min.js
- `constructor()` --indirect_call--> `Xa()`  [INFERRED]
  web/extras/pronunciation/transformers.min.js → web/extras/pronunciation/espeak-ng/espeakng.worker.js
- `ee()` --indirect_call--> `S()`  [INFERRED]
  web/extras/pronunciation/espeak-ng/espeakng.worker.js → web/extras/pronunciation/transformers.min.js
- `he()` --indirect_call--> `S()`  [INFERRED]
  web/extras/pronunciation/espeak-ng/espeakng.worker.js → web/extras/pronunciation/transformers.min.js
- `ld()` --indirect_call--> `S()`  [INFERRED]
  web/extras/pronunciation/espeak-ng/espeakng.worker.js → web/extras/pronunciation/transformers.min.js

## Import Cycles
- None detected.

## Communities (147 total, 67 thin omitted)

### Community 0 - "espeakng.worker.js"
Cohesion: 0.02
Nodes (37): _abort(), abortOnCannotGrowMemory(), allocate(), assert(), ___buildEnvironment(), castObject(), _clock_gettime(), demangleAll() (+29 more)

### Community 1 - "_"
Cohesion: 0.02
Nodes (41): _, Ac, Bn, cc, Cn, Do, Ec, eo (+33 more)

### Community 2 - "ort-wasm-simd-threaded.jsep.mjs"
Cohesion: 0.05
Nodes (79): tb(), a(), ab(), ac(), $b(), Bb(), bc(), bd() (+71 more)

### Community 3 - "ht"
Cohesion: 0.06
Nodes (33): byteLength(), captureBegin(), captureEnd(), computeKernel(), create(), createTemporaryTensor(), destroy(), download() (+25 more)

### Community 4 - "hc"
Cohesion: 0.14
Nodes (33): ad(), ae(), bd(), ce(), cj(), _d(), de(), ee() (+25 more)

### Community 5 - "_f"
Cohesion: 0.08
Nodes (42): ac(), ag(), be(), cf(), cg(), dj(), ed(), ej() (+34 more)

### Community 7 - "evaluate"
Cohesion: 0.10
Nodes (36): applyFilter(), __bool__(), ce(), ee(), evalProgram(), evaluate(), evaluateArguments(), evaluateBinaryExpression() (+28 more)

### Community 9 - "ue"
Cohesion: 0.09
Nodes (32): ab(), af(), bf(), dd(), df(), _e(), ef(), ff() (+24 more)

### Community 10 - "hi"
Cohesion: 0.09
Nodes (32): ai(), ak(), bb(), bi(), bj(), cb(), ck(), eb() (+24 more)

### Community 12 - "ki"
Cohesion: 0.14
Nodes (25): ah(), aj(), bg(), bh(), bk(), cc(), ch(), ci() (+17 more)

### Community 13 - "ve"
Cohesion: 0.13
Nodes (12): at, be(), dt(), It(), Lt(), Me(), ot(), Pt() (+4 more)

### Community 14 - "se"
Cohesion: 0.11
Nodes (19): ci, ed, ei, es, In, jo, ns, qd (+11 more)

### Community 15 - "R"
Cohesion: 0.18
Nodes (5): En(), H(), q(), Qn, R()

### Community 16 - "_e"
Cohesion: 0.13
Nodes (12): Ce, _e(), fe(), format(), G(), ge(), me, Pe() (+4 more)

### Community 17 - "yn"
Cohesion: 0.22
Nodes (9): Jn, kn(), Kn, Mn, Tn(), Vn(), Wn, Xn() (+1 more)

### Community 18 - "ae"
Cohesion: 0.13
Nodes (7): ae, bc, gc, hc, uc, vc, wc

### Community 19 - "LoquiSpeech"
Cohesion: 0.09
Nodes (5): LoquiSpeech, _language, _listening, _session, LoquiSpeechSession

### Community 20 - "de"
Cohesion: 0.18
Nodes (12): constructor(), de(), Ie(), ie, je(), le(), Le, Oe() (+4 more)

### Community 21 - "h"
Cohesion: 0.13
Nodes (3): h, toImageData(), u()

### Community 22 - "cd"
Cohesion: 0.11
Nodes (33): bc(), cd(), dc(), eg(), hc(), hi(), _i(), id() (+25 more)

### Community 23 - "ml"
Cohesion: 0.22
Nodes (6): bl, gl, hl, ml, wl, yl

### Community 24 - "ee"
Cohesion: 0.14
Nodes (18): bn(), Bt(), cn(), createMLContext(), Dt, fn(), gn(), hn() (+10 more)

### Community 26 - "nn"
Cohesion: 0.12
Nodes (16): an, build(), dn(), Fe, Gn, Hn, jn(), ln (+8 more)

### Community 28 - "p"
Cohesion: 0.17
Nodes (3): _c, $e, p()

### Community 31 - "V"
Cohesion: 0.38
Nodes (19): V(), a(), c(), d(), G(), H(), i(), J() (+11 more)

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
Cohesion: 0.09
Nodes (22): compute(), createDownloader(), createMLTensorDownloader(), ct(), Ct, et, fr, ft() (+14 more)

### Community 38 - "gen_phonemes.py"
Cohesion: 0.13
Nodes (6): main(), main(), _phones(), check(), main(), read()

### Community 39 - "AGENTS.md"
Cohesion: 0.12
Nodes (15): Android build specifics, Autoloads (singletons) — registered in `project.godot`, Combat & speech-challenge flow, Export plugin & committed artifacts, Google Sheets integration, Level / travel system, Mic-only voice command mode, Other quirks (+7 more)

### Community 40 - "initialize"
Cohesion: 0.33
Nodes (5): initialize(), onRunStart(), pt, qt, setQueryType()

### Community 42 - "uf"
Cohesion: 0.17
Nodes (15): _c(), jc(), mc(), nc(), oc(), oh(), pc(), rf() (+7 more)

### Community 44 - "f"
Cohesion: 0.18
Nodes (6): D(), f(), i(), fromGpuBuffer(), r(), w()

### Community 45 - "N"
Cohesion: 0.15
Nodes (5): jl, N(), vi, wd, wu

### Community 47 - "ho"
Cohesion: 0.14
Nodes (10): fo, go, ho, ko, no, ro, to, vo (+2 more)

### Community 49 - "dl"
Cohesion: 0.14
Nodes (10): al, cl, dl, il, ll, ol, pl, sl (+2 more)

### Community 50 - "B"
Cohesion: 0.15
Nodes (4): he, j(), L(), z

### Community 53 - "MIDDLE ZONE — Execution Logic, Tool Routing, Diagnostics"
Cohesion: 0.15
Nodes (12): Agentic Output Warning, Credential Safety, Diagnostic Checklist, Input Sanitization -- Pasted Prompts, Intent Extraction, Memory Block, MIDDLE ZONE — Execution Logic, Tool Routing, Diagnostics, PRIMACY ZONE — Identity, Hard Rules, Output Lock (+4 more)

### Community 54 - "c"
Cohesion: 0.20
Nodes (4): c(), P, reshape(), S()

### Community 57 - "callRuntimeCallbacks"
Cohesion: 0.21
Nodes (12): addOnPostRun(), addOnPreRun(), callRuntimeCallbacks(), ensureInitRuntime(), __exit(), exitRuntime(), ExitStatus(), postRun() (+4 more)

### Community 59 - "pr"
Cohesion: 0.10
Nodes (14): br, cr, dr, Er, ir, kr, lr, mr (+6 more)

### Community 60 - "cu"
Cohesion: 0.18
Nodes (5): cu, fu, hu, mu, pu

### Community 61 - "td"
Cohesion: 0.40
Nodes (4): kd, nd, td, vd

### Community 63 - "Rc"
Cohesion: 0.06
Nodes (9): el, Fn, Je, Mt, Ne, pe, Rc, tl (+1 more)

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

### Community 68 - "iu"
Cohesion: 0.17
Nodes (6): au, du, iu, lu, ou, uu

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
Cohesion: 0.50
Nodes (4): ca, ma, pa, ya

### Community 74 - "ensureValid"
Cohesion: 0.33
Nodes (6): data(), ensureValid(), getData(), gpuBuffer(), mlTensor(), texture()

### Community 75 - "Dn"
Cohesion: 0.31
Nodes (4): Dn, ic, lc, run()

### Community 78 - "Ft"
Cohesion: 0.33
Nodes (5): Ft, getCachedTensor(), getMLContext(), registerTensor(), reserveTensorId()

### Community 82 - "Q"
Cohesion: 0.18
Nodes (4): Q, ra, sa, xn

### Community 83 - "build_xcframework.sh"
Cohesion: 0.60
Nodes (4): compile_one(), generate_headers(), PATH, build_xcframework.sh script

### Community 84 - "runWithFS"
Cohesion: 0.50
Nodes (4): finish(), runWithFS(), assert(), processPackageData()

### Community 85 - "sd"
Cohesion: 0.40
Nodes (3): ad, od, sd

### Community 86 - "he"
Cohesion: 0.22
Nodes (10): _b(), ec(), fd(), gd(), hd(), he(), jd(), od() (+2 more)

### Community 87 - "tr"
Cohesion: 0.25
Nodes (7): jr, nr(), rr(), tr(), vr, xr, Zn

### Community 88 - "gu"
Cohesion: 0.40
Nodes (3): bu, gu, yu

### Community 89 - "la"
Cohesion: 0.40
Nodes (3): da, la, ua

### Community 94 - "ii"
Cohesion: 0.50
Nodes (3): di, ii, li

### Community 95 - "W"
Cohesion: 0.20
Nodes (5): ar, er(), sr(), W, x()

### Community 97 - "id"
Cohesion: 0.29
Nodes (4): dd, id, ld, ud

### Community 98 - "bo"
Cohesion: 0.33
Nodes (5): bo, co, mo, po, yo

### Community 99 - "gt"
Cohesion: 0.40
Nodes (3): gt, wt, yt

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
Cohesion: 0.33
Nodes (3): bi, wi, yi

### Community 124 - "ds"
Cohesion: 0.67
Nodes (3): cs, ds, us

## Knowledge Gaps
- **4 isolated node(s):** `_language`, `_listening`, `_session`, `PATH`
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 589 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **67 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_` connect `_` to `ht`, `hc`, `_i`, `evaluate`, `_o`, `i`, `ve`, `se`, `R`, `_e`, `yn`, `ae`, `de`, `h`, `ml`, `ee`, `o`, `nn`, `p`, `_r`, `.push`, `V`, `F`, `l`, `_t`, `M`, `AGENTS.md`, `initialize`, `d`, `_a`, `f`, `N`, `b`, `ho`, `.tokenizer`, `dl`, `B`, `Nc`, `s`, `c`, `v`, `pr`, `cu`, `td`, `k`, `Rc`, `md`, `lo`, `va`, `iu`, `declareVariable`, `ca`, `pd`, `ensureValid`, `Dn`, `.fromConfig`, `g`, `Ft`, `._call`, `Te`, `y`, `Q`, `sd`, `tr`, `gu`, `la`, `Be`, `De`, `ii`, `W`, `Ge`, `id`, `bo`, `gt`, `lt`, `jc`, `ru`, `aa`, `.bpe`, `oi`, `rs`, `ws`, `ga`, `ha`, `fi`, `ps`, `os`, `ji`, `ni`, `bi`, `additionalImplementations`, `processTerm`, `gd`, `bt`, `ds`, `createInferenceSessionHandler`, `rl`, `ja`, `en`, `fetchModelAndCopyToWasmMemory`, `fs`, `mi`, `jt`, `kl`, `lookupVariable`, `normalizeAxes`, `pi`, `qa`, `rd`, `Sn`, `vn`, `xa`?**
  _High betweenness centrality (0.595) - this node is a cross-community bridge._
- **What connects `_language`, `_listening`, `_session` to the rest of the system?**
  _4 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `espeakng.worker.js` be split into smaller, more focused modules?**
  _Cohesion score 0.017163412127440904 - nodes in this community are weakly interconnected._
- **Why does `Y()` connect `evaluate` to `_`, `ort-wasm-simd-threaded.jsep.mjs`, `hc`, `_f`, `f`, `_e`, `c`, `p`, `V`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Should `_` be split into smaller, more focused modules?**
  _Cohesion score 0.017543859649122806 - nodes in this community are weakly interconnected._
- **Why does `N()` connect `N` to `_`, `F`, `hc`, `_f`, `iu`, `pd`, `hi`, `f`, `V`, `R`, `B`, `Q`, `bi`, `cd`, `tr`, `ee`, `cu`, `W`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Should `ort-wasm-simd-threaded.jsep.mjs` be split into smaller, more focused modules?**
  _Cohesion score 0.05343320848938826 - nodes in this community are weakly interconnected._
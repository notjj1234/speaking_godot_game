# Pronunciation spike — results (Phase 0 gate)

Fill this in after running the hands-on checkpoint below. Verdict gates Phase 3:
**threshold 75 must separate correct vs wrong utterances by a clear margin on desktop Chrome.**

## How to run

1. Serve: `python3 build/serve_https.py` (mounts `web/extras/` at `/extras/` and `tools/` at `/tools/`)
2. Open `https://127.0.0.1:8443/tools/pronunciation_spike/index.html` in Chrome, accept the self-signed cert.
3. Click **🔊 Load model (no mic needed)** first — if that fails, nothing else will work; check `<pre>` log.
4. Pick the target word, click **● Record**, say the word, click **■ Stop & score**.
5. Say each of the 10 words once as intended, then once deliberately wrong (a nonsense word or a different
   word's pronunciation), recording scores below.

## Timings

| Metric | ms |
|---|---|
| Model load (ms measured by load()) | |
| Score round-trip (ms measured by endCaptureAndScore) | |
| Worker device used (webgpu / wasm) | |

## Correct vs wrong scores

| Word | Said correctly | Said wrongly | Correct − wrong |
|---|---|---|---|
| hello  | | | |
| water  | | | |
| apple  | | | |
| cat    | | | |
| dog    | | | |
| school | | | |
| friend | | | |
| book   | | | |
| happy  | | | |
| sorry  | | | |

## Verdict

- [ ] Threshold 75 separates correct vs wrong with a clear margin on desktop Chrome → proceed to Phase 3
- [ ] Does not separate cleanly → record margin size and failing words here:


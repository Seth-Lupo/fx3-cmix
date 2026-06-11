# fx3-cmix Architecture (seeded from fx2-cmix README; deep-dive pending)

> Status: **skeleton**. Filled in properly during Phase 1 (code deep-dive). Sections marked TODO need verification against source, not the README.

## Pipeline overview
```
enwik9
  └─ single-pass Wikipedia transform (src/preprocess/, readalike_prepr/)
       • article reordering via precomputed order file (new_article_order,
         generated offline with voyage embeddings + t-SNE + k-means)
       • HTML entities → UTF-8, wiki markup transforms
       • dictionary word-coding (dictionary/english.dic, 44,515 words),
         reverse-dictionary transform done online during decompression
  └─ transformed stream: 934,220,400 bytes
  └─ bit predictor ensemble (461 models) + arithmetic coder
       → 110,111,245 bytes
self-extracting archive = cmix binary + compressed dict + compressed order + header
```

## Components (by source location)
| Area | Files | Notes |
|---|---|---|
| Main NLP/context model "fxcm" | `src/models/fxcmv1.cpp` (**4.8k lines — the heart**) | stemmer-driven word streams, 3 ContextMaps (32/64/128 B/ctx), sparse match model, tag detection (math/pre/nowiki), list/paragraph parsing |
| PPM | `src/models/ppmd.cpp` | ppmd variant; `mmap_to_disk=true` to fit 10 GB RAM (slower, heavy disk writes) |
| cmix framework | `src/predictor.cpp`, `src/runner.cpp`, `src/context-manager.cpp` | model graph assembly, 461 predictors |
| Contexts | `src/contexts/` | bit/bracket/combined/indirect/interval/sparse context hashing |
| Models | `src/models/` | direct, direct-hash, indirect, match, bracket, byte-model |
| Mixers | `src/mixer/` | logistic mixers + SSE/APM stages + one LSTM (`lstm.h`, `lstm-layer.h`, `byte-mixer.cpp`); weight-update skipping below error threshold |
| States | `src/states/` | nonstationary + run-map state tables, generated at runtime (code-size trick) |
| Coder | `src/coder/` | arithmetic encoder/decoder |
| Preprocess | `src/preprocess/`, `src/readalike_prepr/` | dictionary transform, article remap, phda9 preprocessing, self-extraction stub |

## Build
- clang-17, two optimization tiers: hot files `-O3`, cold files `-Os` (binary size counts toward S1!).
- **PGO build** (`build_and_construct_comp.sh`): prof_gen → run on `prof_input/input` → prof_use with LTO → `upx-ucl -9`.
- `-march=native` by default; `COREI7`/`ZEN2` make flags pin the target arch — **submission binary must match committee hardware arch**.
- Compile-time knobs: `SEED=923`, `UPDATE_LIMIT=3000` (CFLAGS defines).

## Known design tensions (= optimization levers)
1. **Time ↔ model complexity**: fx2 deliberately removed cmix predictors (7 indirect, 6 match, 3 mixers) to give fxcm more time budget. ~30% time headroom remains on the reference machine.
2. **RAM ceiling**: 9.5/10 GB used. PPM pushed to disk-mmap. Any new model must steal memory from elsewhere or be tiny.
3. **Binary size**: every byte of code is a byte of S1. Runtime-generated tables, `-Os`, UPX. New code must pay for itself: saving X bytes of archive is void if it adds ≥X bytes of compressed binary.

## Predictor graph (verified from predictor.cpp, 2026-06-10)
461 inputs feed layer-0. Ensemble members, in input order:
1. **bracket_model_** — byte-level bracket model (`models/bracket.cpp`, params 200/10/100000) + 1 direct model + 1 indirect-NS model on a bracket context.
2. **fxcm_model_** (`fxcmv1.cpp`) — multi-output; the dominant predictor.
3. **match models ×10** — 5 on sparse word contexts `{0},{1},{1,3},{1,2,3},{7,2}` + 5 on byte context hashes `{0,8},{1,8},{7,4},{11,3},{13,2}`; limit 200, δ 0.5, ≤2M entries; one run-map indirect on word ctx {1}.
4. **indirect nonstationary ×15** — 10 sparse word-context combos + 4 "double indirect" (ind1/2/3/5) + bracket; δ 200–400, shared map.
5. **byte_model_ = PPMD** — order **25**, **14,000 MB** arena (→ the 14.68 GB `ppm.temp` when mmap_to_disk; this is the single biggest memory object).
6. **byte_mixer_ = LSTM** — `Lstm(vocab, vocab, 200 cells, 1 layer, 128, lr 0.03, 10)`, fed PPM's 256-way byte prediction; its output can **override the whole ensemble** when fully saturated (==0.0 or ==1.0).

**Mixing**: layer-0 = 23 logistic mixers, each with own context + learning rate (0.005 / 0.0005 / 0.001 / 0.002 / 0.0007 / 0.0003 mix); contexts include mx5–mx19, words, line_break, longest_match, recent_bytes[2], auxiliary (= avg of fxcm & LSTM predictions, discretized ×15 — a confidence signal). Layer-1 = 1 final mixer over the 23 stretched layer-0 outputs + fxcm + LSTM directly. Then **SSE** stage. Weight-decay 1e-4; sigmoid LUT 100001 entries.

**Tunable surface spotted** (Phase 2B candidates): 23 mixer learning rates, deltas (200/400/0.5), match limit/size, PPM order & arena size, LSTM hyperparams, auxiliary discretization (×15), SSE params, UPDATE_LIMIT/SEED defines.

## fxcmv1.cpp internal structure (line map, 2026-06-10)
A self-contained paq8-style engine inside one file:
- **~89–360**: squash/stretch LUTs, `Inputs` (64-aligned), ilog, **runtime state-table generation** (`num_states/discount/next_state/generate`, seeded by `Init(s0..s6)` — the state-table search space for experiments).
- **~350–510**: dictionary load + codeword decode (`loaddict/decodeCodeWord/dosym/decodeWord`) — the online reverse-dictionary transform.
- **~512–565**: SIMD mixer kernels `dot_product`/`train` (AVX2 `_mm256_madd_epi16`) — hot loops.
- **~565–1540**: mixer plumbing + **three ContextMap variants** (Init at 921 / 1126 / 1359 = the 32 / 64 / 128-byte-per-context flavors), RunContextMap, StateMaps (`mix1/mix3/mix4/mix`).
- **~1542–1800**: APM, DirectStateMap, MTFList, **SparseMatchModel** (gap 1–2, minlen 3–6, for escaped UTF-8).
- **~1802–2200**: tiny vec, BracketContext, ColumnContext (tables/cells), WordsContext (the 4 word streams).
- **~2221–2600+**: `Word` + `EnglishStemmer` (word types incl. Article/Conjunction/Adposition/ConjunctiveAdverb driving stream filtering).
- Remainder: context wiring, main `mix()` per-bit pipeline, Perceive/Predict glue to cmix.

## TODO (Phase 1 deep-dive)
- [x] Map the top-level predictor graph (above).
- [x] Structural line-map of fxcmv1.cpp (above).
- [ ] Count the 461 inputs exactly per member (fxcm NumOutputs dominates — verify).
- [ ] Extract all ContextMap memory sizes (rebalancing axis) and context definitions in fxcm's wiring section.
- [ ] Trace fxcmv1.cpp: word-stream state machine, ContextMap internals, mixer wiring.
- [ ] Document the transform format byte-for-byte (escape codes, article framing).
- [ ] Profile: where do the ~228k seconds actually go? (fxcm vs PPM vs LSTM vs mixers)
- [ ] Memory map: where do the ~9.5 GB go?

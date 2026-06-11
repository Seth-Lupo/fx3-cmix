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

## TODO (Phase 1 deep-dive)
- [ ] Map the exact predictor graph: all 461 models, their contexts, memory budgets.
- [ ] Trace fxcmv1.cpp: word-stream state machine, ContextMap internals, mixer wiring.
- [ ] Document the transform format byte-for-byte (escape codes, article framing).
- [ ] Profile: where do the ~228k seconds actually go? (fxcm vs PPM vs LSTM vs mixers)
- [ ] Memory map: where do the ~9.5 GB go?

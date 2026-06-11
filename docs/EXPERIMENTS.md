# Experiment Ledger

Every experiment gets a row here — **including null and negative results**. Detailed write-ups go in `docs/experiments/NNN-slug.md` when a result is interesting enough to need one.

## Conventions
- Branch: `exp/NNN-slug` off `main`. NNN is the ledger row id, zero-padded.
- One variable per experiment where possible. Knob sweeps may share a branch with the knob recorded per row.
- Tier ladder: T0 smoke (prof_input/input2, ~1 MB) → T1 proxy (50–100 MB transformed slice) → T2 enwik8-scale → T3 full enwik9. A change is only believed at the tier where it will be claimed; promotion requires winning at the lower tier first.
- Always: same VM size, single core pinned (`taskset -c 0`), PGO build, record git sha of exact tree measured.
- Baseline rows (unmodified fx2-cmix) are measured first at every tier and re-measured whenever the VM/toolchain changes.

## Proxy validation status
**Not yet validated.** No proxy number may be used for a keep/drop decision until the tier ladder is calibrated (Phase 0.4 in PLAN.md).

## Findings log
- **2026-06-10 — fx2-cmix crashes on Linux 6.x kernels (fixed).** The PPM `mmap_to_disk` RSS-dropping cycle (`ppmd.cpp` ByteUpdate, every 20,000 bytes) did `munmap` + `mmap(NULL,…)` and relied on the kernel reusing the same address; ppmd stores absolute pointers into that heap. Linux 6.8 (Ubuntu 22.04 Azure) places the remap elsewhere → deterministic SIGSEGV at the first remap (39.95% of the PGO input). Fixed with an atomic `MAP_FIXED` remap at the original address; output verified byte-identical to `mmap_to_disk=false` (md5 `0888f9d854f06b21d210fef7c13a5562` both ways). Implication: the published fx2-cmix binary is kernel-sensitive — worth noting in any submission write-up; also means judge-machine kernel matters.
- **2026-06-11 — spot evictions**: 2 evictions in ~5h on centralus E2s_v3 spot. Policy: spot1 = sub-hour jobs only; ≥6h runs go on lab1 (on-demand). T2 calibration moved to lab1 post-586M (~Jun 12).
- **2026-06-10 — VM platform**: lab1 = Xeon Platinum 8272CL (Cascade Lake), same µarch generation as fx2's reference c2-standard-4. `-march=corei7` cannot build (fxcmv1 requires AVX2); usable march values: `native`, `znver2`, or ≥haswell.

## Ledger
| ID | Date | Branch / sha | Tier | Dataset | Bytes out | Δ vs baseline | Wall time | Peak RSS | Verdict | Notes |
|----|------|--------------|------|---------|-----------|---------------|-----------|----------|---------|-------|
| 000a | 2026-06-10 | main (mmap fix) | T0 | input2 (930,723 B) | 180,611 | baseline | 5m47s c / 5m50s d | n/a | ✅ round-trip OK | lab1, PGO build, S1=441,983 |
| 000b | 2026-06-10 | main (mmap fix) | T3 | enwik9 | *running* | baseline anchor | est. ~65–75 h | — | ⏳ launched | lab1 core 0, /mnt/work/baseline, expect S2≈110.35 MB |
| 001 | 2026-06-11 | main | T1 | text_10M | 1,065,537 | baseline | 50m54s | 5.99 GB | ✅ anchor | lab1 core 2 (concurrent w/ baseline) |
| 002 | 2026-06-11 | main SEED=1 | T0 | text_1M | 71,314 | −31 B vs 71,345 | 8m38s | 5.73 GB | ✅ noise probe | spot1; seed⊕machine confounded → T0 noise floor ≈ tens of bytes; decision threshold ≥300 B |
| 003 | 2026-06-11 | main | T0 | text_1M | 71,345 | ±0 vs lab1 | 10m14s* | 5.72 GB | ✅ **cross-machine identical** | spot1; sizes are µarch-portable (*wall contaminated by debug contention) |
| 004 | 2026-06-11 | main | T1-mid | text_mid10M | *running* | — | — | — | ⏳ | spot1, mid-file anchor |
| 005 | 2026-06-11 | main (PGO build) | T0 | text_1M | 71,298 | **−47 vs plain** | 4m54s | — | ⚠️ build-config sensitivity | lab1; PGO+LTO changes FP rounding → different (slightly better) output. Rule: experiments plain-vs-plain; final numbers always with submission build recipe |

| 006 | 2026-06-11 | exp/006-lstm-lr016 | T0 | text_1M | 71,453 | **+108** | 5m18s | 5.73 GB | ❌ reject | LSTM lr 0.03→0.016 worse; 0.03 near-tuned |
| 007 | 2026-06-11 | exp/007-ppm-order26 | T0 | text_1M | 71,284 | −61 | 5m32s | 5.72 GB | 🟡 weak positive | below 300B bar; revisit at T1 after fx3 pivot (PPM context changes there) |
| 004 | 2026-06-11 | main | T1-mid | text_mid10M | 1,620,639 | anchor | 1h00m* | 5.96 GB | ✅ anchor | mid-file slice; *wall contaminated by debug contention |
| — | 2026-06-11 | exp/order-v26 | — | — | — | author-measured −147,767 | — | — | 🎯 queued for T3 | kaitz's 2025-04 article order recovered (see ARTICLE-ORDER-NOTES.md); needs full-run validation after baseline completes |

| v26-a | 2026-06-11 | standalone v26 (fixed) | T0 | coded_1M | 101,706 | n/a (different input domain) | 157s c | — | ✅ RT OK | -O3, deterministic post-fix |
| v26-b | 2026-06-11 | standalone v26 (fixed) | T1 | coded_10M | 1,646,440 | n/a | 20m53s | **6.77 GB** | ✅ measured | spot1 core1 (other core busy); RSS sets co-location budget |
| v26-c | 2026-06-11 | standalone v26 (fixed) | T3 | coded_full (586 MB) | *running* | kaitz ladder predicts ≈113.6 M | est ~20 h c + ~20 h d | — | ⏳ | lab1 core3, /mnt/work/v26full; validates fix at scale + true v26 number on our build |

| 008 | 2026-06-11 | exp/008-ppm1750-ram | T0 | text_1M | 71,345 | ±0, **md5-identical** | 5m23s | 5.72 GB | ✅ adopt (inert at T0) | PPM 14000MB-mmap→1750MB-RAM; arena unused at 1MB; frees 12.25GB; validate T2+ |
| 009 | 2026-06-11 | exp/009-match2x | T0 | text_1M | 71,345 | ±0 size, content differs | 5m11s | 5.76 GB | ✅ adopt per author | match table ×2 (+32MB); active but size-neutral at T0 |
| 010 | 2026-06-11 | exp/010-sse-blend | T0 | text_1M | 71,345 | ±0 size, content differs | 8m42s | 5.73 GB | ✅ adopt per author | SSE blend 4,5,12,11→4,7,12,9; size-neutral at T0 |
| next-1 | 2026-06-11 | next-fx3 (008+009+010) | T1 | text_10M | 1,065,539 | **+2** | 1h01m | 6.03 GB | ✅ no regression | steps 1-3 neutral at T1 as expected (capacity gains need scale); PPM-in-RAM RSS fine |

| 011 | 2026-06-11 | exp/011-rm-sparsematch | T0 | text_1M | 71,332 | −13 | 7m57s | 5.72 GB | ✅ adopt+merged | SparseMatchModel removed; num_models 461→459; export plumbing OK |
| 012 | 2026-06-11 | exp/012-rm-4sscm | T0 | text_1M | 71,352 | +7 | 8m02s | 5.72 GB | ⚠️ superseded | num_models edit no-op'd (branched off main); 4 dead exports — robustness datum |
| 012b | 2026-06-11 | exp/012b-rm-4sscm | T0 | text_1M | 71,342 | −3, num_models 455 ✓ | 7m57s | 5.75 GB | ✅ adopt+merged | clean 4-SSCM removal atop next-fx3 |
| 013 | 2026-06-11 | exp/013-knobs-345 | T0 | text_1M | 71,334 | −11, faster (5m07s) | 5m07s | 5.75 GB | ✅ adopt+merged | v26 steps 3-5; WUS cap is a real speed lever |
| 014 | 2026-06-11 | exp/014-pronoun | T0 | text_1M | 71,332 | −2 vs parent | 5m16s | 5.75 GB | ✅ adopt+merged | Pronoun word type (step 8); value unlocks at steps 16/23 |

| 015 | 2026-06-11 | exp/015-skipm1 | T0 | text_1M | 71,338 | +6 (noise) | 5m21s | 5.74 GB | ✅ adopt+merged | skipM1 gates (step 9); value = speed at scale (+11K author) |
| 016 | 2026-06-11 | exp/016-codeword | T0 | text_1M | 71,332 | ±0 | 5m24s | 5.74 GB | ✅ adopt+merged, **decode RT OK** | codeword machinery (step 10) — gate open for sentence contexts |

**next-fx3 cumulative @T0: 71,332-71,338 (−7..−13 vs fx2). Steps merged: PPM-RAM, match×2, SSE blend, −SparseMatch, −4SSCM, st2/WUS/APM knobs, Pronoun, skipM1, codeword machinery.**

**Noise model (T0, 1 MB):** machine Δ=0; SEED Δ≈31 B; build-config (PGO) Δ≈47 B. Decision threshold at T0 stays ≥300 B for single-knob changes; anything smaller needs T1 confirmation.

### ✅ M2 SOLVED (2026-06-11 00:40) — fx3 nondeterminism root cause
`ContextMap3/4::reset()` memset the table from the **raw calloc pointer** for **tmask buckets** instead of the **aligned base for tmask+1** — the cleared window shifts by the allocator's alignment accident `(t−ptr)` ∈ {0,16,32,48} (+1 bucket always missed), leaving process-dependent stale states in the table tail after every per-article reset. Encoder and decoder processes get different alignments → divergence. Fixed in `standalone/fxcm.cpp` (2 lines + comments). **-O3 round-trip passes (100 KB and 1 MB: RT1M_OK, 1 MB→101,706 B; +2 B vs buggy build).** Explains kaitz's year-old "suspected FP mixer" blocker and the dcsm removal in fx2 (same bug class: dcsm-era resets). Hunt method: per-bit prediction trace → prediction-vector slot diff → bucket-walk trace → reset-geometry audit. 1 MB round-trip + 10 MB measurement running.

### M2 divergence hunt — state of evidence (2026-06-11 00:15)
Eliminated: optimizer UB (-O0 fails; 3 real UB sites fixed anyway), ASLR, allocator content (MALLOC_PERTURB_), decode-side memory errors (valgrind clean). Sanitized/emulated runs (ASan, valgrind) are self-consistent; all plain builds diverge encode-vs-decode. **Localized:** first model-state divergence at bit 8020 (input byte 1002), `cmC4[7]` (a per-article-reset 64 KB ContextMap4), context slot 3 = `(indirectWord0Pos&0xffff)*191 + word0 + (stream3bR&63)` (fxcm.cpp:5213). cxt[], bucket offsets, cxtMask, parser flags, and visible state bytes all match through bit 8019 — the read state differs only in-flight (c reads s=0, d reads s=7); crash position shifts with instrumentation (timing/layout sensitive). Disabling slot 3 moves the divergence ≥4 KB later → contributory but not sole site; common factor suspected in `indirectWord0Pos`/`buf()`/`wp[]` position-indirection machinery (fxcm.cpp:4777-4789). Debug tooling in standalone/fxcm.cpp: FXTRACE/FXTRACE2/FXTRACE3 env-gated traces.
Next: per-byte scalar dump (pos, word0, wp[word0], indirectWord0Pos, numberA, indirectNumberd0Pos) in window; group-disable cmC4[7] contexts; audit buf()/bufr() ring indexing for encode/decode asymmetry.

### M1/M2 progress (kaitz fxcm v26 standalone)
- v26 builds on Linux (3-line port, `standalone/`). Compress works (coded_1M → 101,704 B; coded_100k repro). **Decompress segfaults** at `procWord` (fxcm.cpp:4157, bogus codeword → `dictWLen[]` OOB) — encoder/decoder divergence on Linux/clang-17. UBSan flags signed-overflow/shift UB at :2029/:5163/:5235. `-fwrapv` alone does NOT fix. Sanitized round-trip + `-O0` test in progress. Working theory: optimizer-exploited UB → asymmetric miscompile; plausibly related to kaitz's integration determinism bug.

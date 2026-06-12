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

| 017 | 2026-06-11 | exp/017-heading-skip | T0 | text_1M | 71,381 | +49 standalone | 8m40s | 5.73 GB | ✅ merged via stack | heading/category skip (step 11); costs info at 1MB, pays at full scale |
| 019 | 2026-06-11 | exp/019-worcxt stack (11+12+13) | T0 | text_1M | **71,240** | **−92 vs parent** | 8m33s | 5.75 GB | ✅ adopt+merged, **decode RT OK** | PState contexts + worcxt rework; num_models 430 (fxcm) |

| 023 | 2026-06-11 | exp/023-sentences stack (14+15+16+17) | T0 | text_1M | **70,936** | **−304 vs parent, first >300B win** | 5m28s | 6.40 GB | ✅ adopt+merged, **decode RT OK** | SentenceContext + StationaryMaps + wt-hashes + numbers; num models 509 |

| 020 | 2026-06-11 | exp/020-numbers (attribution) | T0 | text_1M | 71,140 | −100 vs parent | 4m16s | 5.75 GB | ✅ (within 023 stack) | numbers step alone |
| 028 | 2026-06-11 | exp/028-resets stack (18+19+20+21+22) | T0 | text_1M | **70,467** | **−469 vs parent** | 4m49s | 7.34 GB | ✅ adopt+merged, **decode RT OK** | cmcr wave+nestList, XML model, ContextMap3/4 class swap w/ FIXED resets, sizes, per-article resets; num models 539; faster |

| 029 | 2026-06-11 | exp/029-mixerbank (23+24) | T0 | text_1M | 70,373 | −94 | 9m25s* | 7.59 GB | ✅ adopt+merged | 18 L0 mixers + integer mxA2/mmmO chain in-fxcm; num models 554 (*contended) |
| 030 | 2026-06-11 | exp/030-dcsm (25, tip) | T0 | text_1M | **70,311** | −62 | 9m46s* | 7.98 GB | ✅ adopt+merged, **decode RT OK** | dcsm ×5 behind FXCM_DCSM; 3rd reset-bug instance pre-fixed; num models 559 |

**🏁 PORT COMPLETE: next-fx3 @T0 = 70,311 (−1,034 B = −1.45% vs fx2 71,345). All 25 map steps merged, every decode-RT gate green, the historic nondeterminism bug class fixed in 3 places. RAM ≈9.6 GiB projected (trims identified; FXCM_DCSM=0 kill-switch available). Next: T1/T2 scaling, RAM measurement, order+model combined T3.**

| next25-t1 | 2026-06-11 | next-fx3 (full 25-step tip) | T1 | text_10M | **1,051,498** | **−14,039 = −1.32% vs 1,065,537** | 56m48s | **7.89 GB** | ✅ **scaling confirmed** | exp1 single-tenant; T0 −1.45% → T1 −1.32%, gain holds at 10× scale; FXTRACE hygiene verified (integrated model clean, instrumentation only in standalone/) |

**Scaling readout:** the port's relative gain is stable across tiers (−1.45% @1MB, −1.32% @10MB). If −1.3% holds at T3, model-side alone ≈ −1.45M on fx2's 110.35M S2 — comfortably past the 50,431 B shortfall even before the article-order −147,767. Peak RSS 7.89 GB at T1 with PPM arena at 1750MB-RAM; full-scale RAM remains the open compliance question (projection ≈9.6 GiB).

**Probe queue launched 2026-06-11 on spot2** (T0 sanity + T1 signal each, vs next-fx3 tip T1 = 1,051,498): exp/031 mxA2[3] 0x10000→0x8000 (−35 MiB), exp/032 cmC2[4] 16→8×4096×4096 (−256 MiB), exp/033 cmC2[5] same (−256 MiB), exp/034 cmcr2 halved (−64 MiB, sensitivity test for full disable), exp/035 PPM order 26 retest atop tip (−61 @T0 pre-port). Purpose: price each RAM trim in bytes for the strict-10GB decision; o26 is the one cheap upside knob the port reshuffled. Note: dcsm 28→27 (−256 MiB) is ALREADY in the port (exp 030 shipped 27 bits vs v26's 28). Expectation per exp/008 precedent: memory trims ≈ invisible at T0; T1 is the signal tier; final pricing needs T2.

**Noise model (T0, 1 MB):** machine Δ=0; SEED Δ≈31 B; build-config (PGO) Δ≈47 B. Decision threshold at T0 stays ≥300 B for single-knob changes; anything smaller needs T1 confirmation.

### ✅ M2 SOLVED (2026-06-11 00:40) — fx3 nondeterminism root cause
`ContextMap3/4::reset()` memset the table from the **raw calloc pointer** for **tmask buckets** instead of the **aligned base for tmask+1** — the cleared window shifts by the allocator's alignment accident `(t−ptr)` ∈ {0,16,32,48} (+1 bucket always missed), leaving process-dependent stale states in the table tail after every per-article reset. Encoder and decoder processes get different alignments → divergence. Fixed in `standalone/fxcm.cpp` (2 lines + comments). **-O3 round-trip passes (100 KB and 1 MB: RT1M_OK, 1 MB→101,706 B; +2 B vs buggy build).** Explains kaitz's year-old "suspected FP mixer" blocker and the dcsm removal in fx2 (same bug class: dcsm-era resets). Hunt method: per-bit prediction trace → prediction-vector slot diff → bucket-walk trace → reset-geometry audit. 1 MB round-trip + 10 MB measurement running.

### M2 divergence hunt — state of evidence (2026-06-11 00:15)
Eliminated: optimizer UB (-O0 fails; 3 real UB sites fixed anyway), ASLR, allocator content (MALLOC_PERTURB_), decode-side memory errors (valgrind clean). Sanitized/emulated runs (ASan, valgrind) are self-consistent; all plain builds diverge encode-vs-decode. **Localized:** first model-state divergence at bit 8020 (input byte 1002), `cmC4[7]` (a per-article-reset 64 KB ContextMap4), context slot 3 = `(indirectWord0Pos&0xffff)*191 + word0 + (stream3bR&63)` (fxcm.cpp:5213). cxt[], bucket offsets, cxtMask, parser flags, and visible state bytes all match through bit 8019 — the read state differs only in-flight (c reads s=0, d reads s=7); crash position shifts with instrumentation (timing/layout sensitive). Disabling slot 3 moves the divergence ≥4 KB later → contributory but not sole site; common factor suspected in `indirectWord0Pos`/`buf()`/`wp[]` position-indirection machinery (fxcm.cpp:4777-4789). Debug tooling in standalone/fxcm.cpp: FXTRACE/FXTRACE2/FXTRACE3 env-gated traces.
Next: per-byte scalar dump (pos, word0, wp[word0], indirectWord0Pos, numberA, indirectNumberd0Pos) in window; group-disable cmC4[7] contexts; audit buf()/bufr() ring indexing for encode/decode asymmetry.

### M1/M2 progress (kaitz fxcm v26 standalone)
- v26 builds on Linux (3-line port, `standalone/`). Compress works (coded_1M → 101,704 B; coded_100k repro). **Decompress segfaults** at `procWord` (fxcm.cpp:4157, bogus codeword → `dictWLen[]` OOB) — encoder/decoder divergence on Linux/clang-17. UBSan flags signed-overflow/shift UB at :2029/:5163/:5235. `-fwrapv` alone does NOT fix. Sanitized round-trip + `-O0` test in progress. Working theory: optimizer-exploited UB → asymmetric miscompile; plausibly related to kaitz's integration determinism bug.

**Creative probe batch (queue2, spot2, 2026-06-11 night):** two macro-parameterized branches sweep seams the candidate list never covered. exp/036-reset-cadence: per-article CM resets were broken for a year (the bug) and never *policy*-tuned — kaitz's own DMC datum says "when to reset" is the lever, so sweep cadence {1=v26, 2, 8, off}. exp/037-sta-tune: STA6/STA7 state-table generator params (b[5], mdc) exposed as defines — author's data shows table identity is the most size-sensitive knob in the system (paq8 swap = −319,523) and the generator params were never swept; grid = mdc±1, b5±1 for both tables. Both branches default-equal to tip → 036sane/037sane runs must reproduce T0 70,311 byte-identically (regression gate). 13 T0 runs ≈ 3h. Deferred creative leads: (a) export pruning — port exports all ~560 fxcm predictions to cmix vs kaitz's ~487 subset and his "one good predictor can hurt cmix a lot" finding; needs export-path surgery, prep tomorrow; (b) blpos magic constants (448131719 / 451531986 "77.06%") are absolute offsets tuned on the OLD article order — interaction with exp/order-v26 only testable at T3; (c) article-order refinement (kaitz missed ~10k of 85,560 redirects) — offline data work, runnable on the Mac, T3 validation.

**spot3 (northcentralus, 20.80.25.248) added 2026-06-11** — second-region spot lane (region policy allows only centralus+northcentralus of the SKU-bearing regions; per-region quota = fresh 6+3 vCPUs; northcentralus on-demand reserved for T3 validation). Queue3 runs exp/037b-sta-all: STA1/2/4/5 mdc ±1 (8 runs + byte-identity sanity), completing coverage of the state-table generator surface alongside queue2's STA6/7 grid.

| 031-t0 | 2026-06-11 | exp/031-mxA2-3-half | T0 | text_1M | 70,312 | +1 vs tip 70,311 | 5m43s | 7.58 GB | ✅ free at T0 | mxA2[3] −35MiB; T1 re-queued (spot2 evicted mid-run, ephemeral disk wiped — ledger/slices/queues rebuilt) |
| 037b-* | 2026-06-11 | exp/037b-sta-all | T0 | text_1M | 70,310–70,313 | **±2 = noise, all 6 of 8 so far** | ~6m each | 7.6 GB | 🟡 flat | STA1/2/4 mdc±1 indistinguishable from sanity at T0 — v26 mdc values sit on a flat optimum (or T0 lacks power); widening STA6/7 grid to mdc±4 in queue2 rewrite |

**Ops lesson (spot eviction):** deallocation wipes /mnt/work entirely (ephemeral disk) — queue scripts, ledger, slices. Recovery = setup.sh + slice relay + queue rewrite; in-flight run lost. Ledger rows must be batch-copied into this file promptly, not left on spot boxes.

| 037b full | 2026-06-11 | exp/037b-sta-all | T0 | text_1M | 70,310–70,313 | **all 8 mdc±1 points flat (±2B)** | ~6m each | 7.6 GB | ❌ null result | STA1/2/4/5 mdc is locally optimal (or T0 powerless here); queue2's STA6/7 mdc±4 grid is the wider test. Null chronicled per convention |

**exp/038 launched (spot3 queue4):** APM-chain scalar export prune — the 7 update-level scalars (pr, pu, pv×2, pt, pz, pr_final) keep feeding fxcm's internal fp-mixers but export neutral 0.5 to cmix behind FXCM_EXPORT_PRUNE=1 (approximates removal without num_models plumbing). Tests kaitz's "one good predictor in fxcm can make compression worse in cmix" against our export-all port choice. Runs: sanity (must = 70,311) + prune at T0 + prune at T1.

| 038sane | 2026-06-11 | exp/038-export-prune | T0 | text_1M | 70,311 | ±0 ✓ gate green | 5m53s | 7.6 GB | ✅ sanity | default build identical to tip |
| 038prune | 2026-06-11 | exp/038-export-prune | T0/T1 | text_1M/10M | 70,359 / 1,052,697 | **+48 @T0, +1,199 @T1** | 6m / 54m | 7.9 GB | ❌ **reject — scalars are load-bearing** | neutralizing the 7 APM-chain scalar exports to cmix hurts decisively; our export-all port choice validated; kaitz's "fewer exports" caution does not apply to these slots |
| 031-t1 | 2026-06-11 | exp/031-mxA2-3-half | T1 | text_10M | 1,051,499 | **+1 vs tip — FREE** | 1h01m | 7.86 GB | ✅ **adopt as RAM trim** | mxA2[3] 0x10000→0x8000 = −35 MiB at zero size cost through T1 |
| 032-t0 | 2026-06-11 | exp/032-cmC2-4-rollback | T0 | text_1M | 70,311 | ±0 | 6m08s | 7.37 GB | ⏳ T1 running | cmC2[4] 16→8×4096×4096 (−256 MiB); RSS already −210 MB at T0 |

**Spot strategy abandoned for tonight (2026-06-11 ~20:45 UTC):** spot2 evicted twice and idle spot3 evicted once — 3 evictions in one evening across BOTH regions (capacity reclaim, utilization-independent). Remaining ~20 probe runs moved to lab2 cores 1-2 (on-demand, idle until the 10:30 UTC T3 gate; queueA = RAM trims on core 1, queueB = 036/037 creative batch on core 2, 60s stagger for git lock). Both spot boxes left deallocated. Loss: 032-t1 in-flight (requeued).

| 036 all | 2026-06-11 | exp/036-reset-cadence | T0 | text_1M | 70,311 ×4 | **sane=c2=c8=off, all identical** | ~9m each | 7.6 GB | 🔬 **T0 is BLIND for resets** | the page-end reset trigger (cwPAGE codeword sequence) never fires inside the 1MB slice — cadence question promoted to T1 (queueC armed: 036c2-t1, 036off-t1). Methodology datum: structural/boundary-triggered features need slices containing the trigger |
| 037sane | 2026-06-11 | exp/037-sta-tune | T0 | text_1M | 70,311 | ±0 ✓ gate green | 9m25s | 7.6 GB | ✅ sanity | STA6/7 wide grid (mdc±4, b5±1) running on core 2 |

| 032-t1 | 2026-06-11 | exp/032-cmC2-4-rollback | T1 | text_10M | 1,051,498 | **±0 vs tip — FREE** | 1h20m | 7.64 GB | ✅ **adopt as RAM trim** | cmC2[4] 16→8×4096×4096 = −256 MiB at zero size cost through T1. Banked trims now: 031 −35MiB + 032 −256MiB + dcsm-27bit −256MiB ≈ −547MiB |
| 037 wide | 2026-06-11 | exp/037-sta-tune | T0 | text_1M | 70,308–70,353 | s6m18 +6, s6m26 −3, s6b2 +1, s6b4 +42 | ~9m each | 7.6 GB | ❌ null (closes STA line) | even mdc±4 and b5±1 on STA6 are sub-threshold — state-table generator params are at a flat optimum; STA7 points finishing then line closed |

| order-delta | 2026-06-11 | (data experiment, lab2 core3) | S1 | new_article_order (1,094,862 B) | cmix raw **199,434** vs delta 208,316 | **delta +8,882 — REJECT** | ~10m each | — | ❌ proxy trap confirmed | xz said delta −50KB; real cmix says raw wins — cmix's context models exploit absolute-index structure that deltas destroy. Same trap as kaitz's 7z-ppm dictionary failure. Rule held: never adopt off a proxy compressor. comp_order is already only ~199KB under cmix — S1 diet here is thinner than hoped |
| 033-t0 | 2026-06-11 | exp/033-cmC2-5-rollback | T0 | text_1M | 70,311 | ±0 | 9m27s | 7.37 GB | ⏳ T1 in flight | cmC2[5] −256MiB candidate |
| 037 s7 wide | 2026-06-11 | exp/037-sta-tune | T0 | text_1M | 70,313–70,378 | +2..+67, all sub-threshold | ~10-16m | 7.6 GB | ❌ **STA line CLOSED** | full generator surface swept (6 tables, mdc±1/±4, b5±1): no signal anywhere. v26 state tables are optimal. QUEUEB-DONE |
| v26-c C_DONE | 2026-06-11 | standalone v26 (fixed) | T3 | coded_full 586MB | **113,264,781** | consistent w/ kaitz ladder (113.2-113.6M band, old-order input) | ~17.5h compress | — | ✅ **port basis validated at scale** | our Linux build of fixed v26 reproduces author's published numbers; decompress leg auto-started (chain) → RT_STATUS = determinism proof, ETA ~Jun 12 late |
| next25-t2 | 2026-06-11 | next-fx3 tip | T2 | text_100M | ≈14,091,687 (99.99%, final pending) | baseline A/B leg auto-started | ~10h | pending time.log | ⏳ | fx2main-t2 chain running → CHAIN_DONE ~09:30 UTC Jun 12; A/B = the T3 gate |

**Archive-residual analysis (2026-06-12, answers "is there correlation left in the archive?"):** (1) Byte-level: tip T2 output is incompressible — xz -9 makes it larger (14,093,920 vs 14,093,160), gzip too. No residue. (2) Rate-profile level (bits/byte per 10KB window from progress.log): mean 1.128 b/B; top-decile windows carry only 13.7% of output bits (uniform = 10%) → **no localized pathology, the headroom is a thin film everywhere** — signature of a mature model. Sole hotspot (3.75-3.77%, ~2.0 b/B) = ancient-history year articles: templated pages dense with one-off named entities (irreducible first-occurrence entropy); the adjacent cheapest window (0.037 b/B) is the same template repeating — structure already fully exploited. Conclusion: supports strategy of side-info/ordering + memory rebalance over model surgery; rate-profile DIFF (tip vs fx2 baseline at T2) still pending baseline completion — will show where the port's −1.3% comes from.

| 033-t1 | 2026-06-11 | exp/033-cmC2-5-rollback | T1 | text_10M | 1,051,503 | +5 (noise) — **FREE** | 1h22m | 7.64 GB | ✅ **adopt as RAM trim** | cmC2[5] 16→8×4096×4096. **Banked trims now ≈ −803MiB all free thru T1** (031 −35, 032 −256, 033 −256, dcsm −256) → projected full-scale RSS ≈ 8.8GiB vs 10GB limit — strict compliance effectively solved |
| 034-t0 | 2026-06-11 | exp/034-cmcr2-half | T0 | text_1M | 70,311 | ±0 | 9m01s | 7.55 GB | ⏳ T1 running | cmcr2 family halved (−64MiB) |

| thp-ab | 2026-06-12 | fx3-candidate PGO binary | T0 | text_1M | md5 IDENTICAL (4c097ccd…) | wall **14:32.85 → 13:27.00 = −7.5%** | — | 7.97 GB | ✅ **adopt for all timed runs** | `GLIBC_TUNABLES=glibc.malloc.hugetlb=1` — only 28% of the 8GB working set was on huge pages (smaps); tunable forces MADV_HUGEPAGE on malloc arenas. Output provably identical, ~3.5h of the ~46h submission time budget for free. perf profile separately confirmed NO code hotspots (flattest distribution, top fn 6.3% — memory system, not code, is the lever) |

| 034-t1 | 2026-06-12 | exp/034-cmcr2-half | T1 | text_10M | 1,051,581 | **+83 — first non-free trim, REJECT** | 1h22m | 7.82 GB | ❌ keep cmcr2 full | −64MiB not needed; −803MiB already banked free |
| 035-t0 | 2026-06-12 | exp/035-ppm-o26-tip | T0 | text_1M | 70,253 | **−58** (pre-port: −61 — replicated) | 9m00s | 7.60 GB | ⏳ T1 confirming | PPM order 25→26 atop tip; consistent direction twice, sub-threshold alone |

**Embedding reorder pipeline (Mac, 2026-06-12 ~03:30 UTC):** full pipeline built and run — segmentation replicates article_reorder.h enumeration exactly (172,315 non-redirect articles, index space matches kaitz's order file); all-MiniLM-L6-v2 embeddings of 172,315 articles in 9 min on M1/MPS; greedy kNN(128) tour in 7.5 min. **Adjacency scoreboard (mean adjacent cosine): original 0.227 → kaitz v26 0.425 → our tour 0.642.** Tour's margin over kaitz ≈ kaitz's margin over original (worth −147,767 real bytes). Caveats: tour optimizes its own metric (home-field bias); adjacency is a proxy — adoption requires real-pipeline measurement per the twice-burned proxy rule. Candidate file: reorder/order_minilm_greedy (172,315 entries, count2 space; orders can't break correctness — unlisted articles append). Next: (a) verify order swaps cleanly through preprocessing on a VM (minutes), (b) optional stronger-embedding arm + or-opt, (c) real A/B gated on T3 readout per PLAN decision rule. fallbacks=3560 (2%) — tour quality has headroom.

| 035-t1 | 2026-06-12 | exp/035-ppm-o26-tip | T1 | text_10M | 1,051,532 | **+34 — T0 signal inverted, REJECT** | 1h18m | 7.89 GB | ❌ PPM order 25 stands | −58@T0 (×2 replicated) did not scale; knob closed |

**XARCH ALERT (open):** AMD decode of Intel-made T0 archive pegged a core for 3h+ (Intel decode of same: ~10 min), output frozen at 413,696/1,000,000 since progress hit 99.99%. Intel control decode launched on lab2 (same binary+archive). If control passes → cross-µarch decode divergence is REAL (suspect: glibc IFUNC per-CPU math dispatch — expm1f32 is in the hot path per perf — giving last-bit FP differences between vendors → arithmetic-decoder desync). If control fails → archive/PGO-binary defect independent of arch. Either way submission-critical; this is why the test exists.

**XARCH CONFIRMED (2026-06-12 ~04:00 UTC): cross-µarch decode divergence is REAL.** Intel control: same binary (PGO, md5 59f172bb) + same archive → decoded md5 = text_1M exactly (13m50s). AMD (EPYC 7763): output desyncs (~41% of plaintext) then pathological spin at 99.99%, 3h+ pegged core, killed. Same glibc 2.35 both boxes → runtime IFUNC dispatch selects different libm code paths by CPUID (expm1f32 is in the hot path per perf) → last-bit FP differences → arithmetic-decoder desync. DISCRIMINATING TEST RUNNING: AMD decode with GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-AVX,-FMA,-AVX512F (masks glibc's dispatcher only; our compiled AVX2 is IEEE-deterministic cross-vendor). If it passes → hypothesis confirmed + env-var mitigation exists; durable fix = bundle deterministic exp/expm1 (no dispatch) into the binary. IMPACT: gates SUBMISSION (judge µarch unknown), does NOT gate the T3 run (same-machine RT unaffected). This was the historic fx2/fx3 "FP mixer" ghost — now with a mechanism.

**XARCH addendum: encoder diverges too.** AMD compress of identical text_1M with identical binary → 70,284 B, md5 38a26f2e ≠ Intel's 4c097ccd. Both directions diverge ⇒ defect is in the shared predictor path (not coder plumbing) — consistent with IFUNC-libm. Encode is now the fast repro (one ~15min run, md5 compare). Masked decode in flight, past the unmasked desync region.

**🎯 XARCH ROOT CAUSE (2026-06-12 ~06:00 UTC): `-ffp-model=fast` (upstream fx2 makefile, whole build) licenses clang to emit `vrcpps` approximate-reciprocal instructions — 17 in the shipped binary. VRCPPS results are architecturally unspecified (only an error bound) and Intel/AMD implement different approximations → deterministic-per-vendor, divergent-across-vendor predictions → arithmetic coder desyncs.** Elimination chain: same glibc + same hwcaps (both AVX2+FMA, no AVX512) ruled out libm dispatch; masked vs unmasked AMD decodes produced byte-identical wrong output (md5 dfd16908 both) ruling out ALL glibc selection effects; binary scan found the vendor-divergent instructions. This is the most plausible identity of kaitz's multi-year cross-machine "FP mixer" ghost (fx2 component deletion, fx3 abandonment, Windows/Linux mismatches). FIX (exp 040): `-mrecip=none` on both compile parts — keeps fast-math speed, forbids only approximate-reciprocal codegen (exact division is IEEE-deterministic). Outputs shift slightly (new baseline numbers); rebuild + Intel RT + cross-arch encode A/B in flight. T3 launch will use the FIXED binary (submission-grade determinism).

| fx2main-t2 | 2026-06-12 | main (fx2) | T2 | text_100M | **14,190,889** | baseline anchor | ~10h | (time.log exp1) | ✅ anchor | exp1 chain; **A/B: tip 14,093,160 = −97,729 = −0.69%** |

**⚠️ GATE READOUT: model-side gain ATTENUATES with scale: −1.45% (T0) → −1.32% (T1) → −0.69% (T2).** Below the −1.0% rule threshold → **rebalance (exp/039, reads out ~10:00 UTC) + embedding reorder are now NECESSITY-tier.** Counterweight: kaitz's 0.954% is a measured END-TO-END T3 number with this model+order — slices are proxies and several v26 mechanisms (sentence/codeword machinery, article-boundary features) plausibly need whole-file structure; the T3 anchor run (launching with the fixed binary) is the ground truth.

| 036off-t1 | 2026-06-12 | exp/036-reset-cadence | T1 | text_10M | 1,051,498 | exact tip | 1h22m | 7.89 GB | 🔬 cadence line T0+T1-BLIND | reset trigger never fires in mid-stream slices; reset policy measurable only at T2+/full — iteration-2 with page-boundary-containing input |

**exp/040 phase 1: fixed binary verified** — vrcp_count=0, PGO rebuild OK (binary md5 cee79eda), new Intel T0 encode md5 72b273fa (expected shift from 4c097ccd — exact division ≠ approximation). Intel RT + AMD cross-encode next; if AMD md5 = 72b273fa → cross-µarch determinism FIXED.

**✅ XARCH FIXED & PROVEN (2026-06-12 05:50 UTC):** AMD Zen3 encode with -mrecip=none binary → md5 72b273fa = bit-identical to Intel Broadwell. Intel RT also green (decode = original). One compiler flag kills the bug class that plausibly blocked fx2/fx3 cross-machine work for two years. Fix propagated to fx3-candidate, next-fx3, main. amd1 deleted (+IP). Total investigation cost: ~$0.50 of AMD VM time. NOTE: all future cross-build comparisons use post-040 numbers (T0 tip = 70,223 under fixed binary vs 70,311 old — the fix itself is byte-POSITIVE at T0, −88!).

**🚀 T3 LAUNCHED (2026-06-12 05:55 UTC):** fx3-candidate (port + kaitz order + RAM trims-in-branch? NO — trims not merged to candidate; candidate = port+order only) full enwik9 -e run on lab2 core0, FIXED PGO binary (md5 cee79eda), hugetlb on. ETA 50-75h → Jun 14-15. Expect S2 in the 108.7-109.3M band (T2 attenuation makes the low end uncertain; kaitz's end-to-end 0.954% is the anchor). Watch RSS vs 10GB and progress.log.

| 039-t2 | 2026-06-12 | exp/039-cmC2-10-double | T2 | text_100M | 14,092,884 | **−276 vs tip 14,093,160 — weak, below bar** | 11h29m | 9.36 GB | 🟡 not adopted | +256MiB buys ~0.3KB at T2 (~1-3KB-class at T3) — memory rebalance on cmC2[10] is NOT the 50K lever; predictor-gains doc winners may map elsewhere, but each datapoint costs ~11h → line deprioritized. **Reorder = primary gap-closer per decision tree.** fx2main-t2 RSS addendum: 7.28 GB |

**T3 rate curve (lab2, contended by 039 until 11:30 UTC):** 0.31@06:30, 0.63@06:57, 0.94@07:29, 1.25@08:01, 1.56@08:33, 1.90@09:04, 2.22@09:35, 2.57@10:07, 2.90@10:38, 3.23@11:10 — steady 0.62-0.66%/h contended; uncontended window begins now, ETA decision next read.

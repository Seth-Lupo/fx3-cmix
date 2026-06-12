# fx3-cmix — Hutter Prize Submission Draft

> STATUS: DRAFT. All TBD fields fill at T3 readout (~2026-06-18) and submission-build validation.

## Result

| Metric | Value |
|---|---|
| Compressor executable size (S1) | **455,757** first packaged measure (fx2: 441,983 our / 441,463 published; kaitz fx3: 437,663) — S1-diet in progress |
| Self-extracting archive size (S2) | **TBD** (primary T3 in flight; expect ~108.7–109.3M) |
| Total S = S1 + S2 | **TBD** |
| Previous record L (fx2-cmix, 2024) | 110,793,128 |
| Improvement 1 − S/L | **TBD** (target ≥ 1% → S ≤ 109,685,196) |
| Running time | **TBD** h on **TBD** machine, Geekbench5 single-core T = **TBD** → budget 70,000/T h |
| RAM max | **TBD** kB (trimmed build projected ≈ 8.8 GiB; limit 10 GB) |

## What this submission is

fx3-cmix completes the unfinished fx3 line of Kaido Orav (kaitz), author of the fx-cmix/fx2-cmix
record holders. The model improvements are his published fxcm v26 work (github.com/kaitz/fxcm) and
his improved article ordering, which he measured end-to-end at 0.954% but never submitted because of
a decompression-determinism failure he could not locate. This work:

1. **Ports all 25 v26 model steps** into the fx2-cmix framework (docs/V26-INTEGRATION-MAP.md),
   each step measured and decode-round-trip-gated (docs/EXPERIMENTS.md ledger).
2. **Fixes two latent nondeterminism bugs** that plausibly blocked the original line:
   - *Reset-alignment bug*: `ContextMap3/4::reset()` (and `DirectStateMap`) memset from the raw
     calloc pointer for `tmask` buckets instead of the aligned base for `tmask+1` buckets —
     allocator-alignment-dependent stale state after per-article resets, i.e. encoder/decoder
     divergence across processes. Fixed in 3 sites.
   - *Vendor-divergent reciprocals*: the upstream makefile's `-ffp-model=fast` lets clang emit
     `vrcpps` (17 instances), whose results are architecturally unspecified and differ between
     Intel and AMD → cross-microarchitecture encoder/decoder divergence. Fixed with `-mrecip=none`;
     proven by bit-identical archives produced on Xeon Broadwell and EPYC Zen3 (and the fix is
     byte-positive: −88 B at the 1MB tier).
3. **RAM compliance**: kaitz's fx3 measured 10,058,856 kB (over a 10⁹-byte reading of the limit).
   Adopted trims measured size-free through the 10MB tier: mxA2[3] halving (−35 MiB), cmC2[4] and
   cmC2[5] doubling rollbacks (−256 MiB each), dcsm 27-bit (−256 MiB) → projected ≈ 8.8 GiB.
4. **Article ordering**: ships kaitz's 2025 order (his measured −147,767) — possibly superseded by
   a sentence-transformer + greedy-tour reorder (A/B in flight; adjacency 0.642 vs 0.425). **TBD**.
5. **Runtime**: `GLIBC_TUNABLES=glibc.malloc.hugetlb=1` (−7.5% wall, output-identical, md5-verified)
   keeps the run inside the time budget with margin.

## Credit

The decisive majority of the modeling work is Kaido Orav's (fxcm v26, the fx3 design, the article
order), building on Byron Knoll's cmix and the fx/fast-cmix/starlit/cmix-hp lineage. Our contribution
is the integration port, the two determinism fixes, RAM/time compliance, and validation.
**Outreach/co-submission decision: TBD (user).**

## Reproducibility

- Source: github.com/Seth-Lupo/fx3-cmix, branch **TBD-submission-tag** (GPL-3.0).
- Build: `build_and_construct_comp.sh` (clang-17, PGO via prof_gen → llvm-profdata → prof_use + LTO,
  upx-ucl; includes `-mrecip=none`). SEED=923, UPDATE_LIMIT=3000.
- Run: `GLIBC_TUNABLES=glibc.malloc.hugetlb=1 ./cmix -e enwik9 enwik9.comp` (compress);
  self-extracting archive decompresses without arguments per fast-cmix conventions.
- Measured on: **TBD** (Azure Standard_E4s_v3, Xeon E5-2673 v4, Ubuntu 22.04, kernel **TBD**) —
  plus cross-microarchitecture decode verification on AMD EPYC 7763.
- Note for committee machines on Linux ≥6.x kernels: upstream fx2's `mmap_to_disk=true` path
  crashes (munmap/mmap address-reuse assumption); this build uses PPM-in-RAM (1,750 MB), which is
  also faster.

## Verification evidence chain

| Check | Status |
|---|---|
| Per-step decode round-trips at 1MB tier (all 25 port steps) | ✅ ledger |
| Full-scale standalone v26 compress (586MB → 113,264,781, in author's band) | ✅ |
| Full-scale standalone v26 decompress round-trip (586MB byte-exact) | ✅ 2026-06-12 |
| Cross-process determinism (reset-alignment fix) | ✅ ASan/Valgrind/elimination chain |
| Cross-microarchitecture determinism (Intel↔AMD bit-identical archives) | ✅ |
| T3 compress (the submission number) | **TBD ~Jun 18** |
| T3 decode round-trip on submission build | **TBD** |
| RAM max on submission build (trimmed) | **TBD** |
| Geekbench5 T-value + adjusted time | **TBD** |

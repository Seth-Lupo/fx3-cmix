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
- **2026-06-10 — VM platform**: lab1 = Xeon Platinum 8272CL (Cascade Lake), same µarch generation as fx2's reference c2-standard-4. `-march=corei7` cannot build (fxcmv1 requires AVX2); usable march values: `native`, `znver2`, or ≥haswell.

## Ledger
| ID | Date | Branch / sha | Tier | Dataset | Bytes out | Δ vs baseline | Wall time | Peak RSS | Verdict | Notes |
|----|------|--------------|------|---------|-----------|---------------|-----------|----------|---------|-------|
| 000a | 2026-06-10 | main (mmap fix) | T0 | input2 (930,723 B) | 180,611 | baseline | 5m47s c / 5m50s d | n/a | ✅ round-trip OK | lab1, PGO build, S1=441,983 |
| 000b | 2026-06-10 | main (mmap fix) | T3 | enwik9 | *running* | baseline anchor | est. ~65–75 h | — | ⏳ launched | lab1 core 0, /mnt/work/baseline, expect S2≈110.35 MB |

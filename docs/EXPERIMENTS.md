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

## Ledger
| ID | Date | Branch / sha | Tier | Dataset | Bytes out | Δ vs baseline | Wall time | Peak RSS | Verdict | Notes |
|----|------|--------------|------|---------|-----------|---------------|-----------|----------|---------|-------|
| — | — | — | — | — | — | — | — | — | — | no experiments yet |

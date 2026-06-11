# fx3-cmix Master Plan — beat fx2-cmix by ≥1%

**Goal:** S ≤ 109,685,196 bytes (save ≥ 1,107,932 bytes vs L = 110,793,128) within Hutter Prize constraints (single core, <10 GB RAM, <100 GB disk, <70,000/T hours).

**Operator model:** Claude (autonomous research agent) runs experiments on Azure x86-64 VMs; the local M1 Mac is orchestration-only (wrong arch — never benchmark or build submission binaries here). Everything chronicled in this repo.

---

## Phase 0 — Infrastructure (first)
Build the autoresearch loop before touching the model.

1. **Provision dev VM** (see [INFRA.md](INFRA.md)): x86-64, 4 vCPU / 16 GB, Ubuntu 22.04/20.04, clang-17 + upx-ucl. One persistent "lab" VM for builds and short experiments; bigger/spot VMs spun up per long run.
2. **Reproduce the baseline build**: `./build_and_construct_comp.sh` must produce a working `cmix`; verify round-trip (compress + decompress, byte-identical) on `prof_input/input2` and on an enwik8-sized slice.
3. **Experiment harness** (`exp/` tooling, new): one command that takes a git ref + dataset + knobs, builds with PGO, runs compress (and optionally round-trip verify), and appends a row to the ledger: `{exp id, git sha, dataset, bytes out, wall time, peak RSS, notes}`. Deterministic, machine-pinned, always single-threaded.
4. **Proxy benchmark validation** (critical): full runs cost ~50 h, so iterate on slices. Candidates:
   - first 50 MB / 100 MB of *transformed* enwik9 (skips transform cost, exercises the predictor);
   - enwik8 (10^8 bytes) as mid-tier check;
   - the existing `prof_input/input2` (~1 MB) for smoke tests only.
   Validate by measuring 3–4 historical commits (fx-cmix → fx2-cmix changes) on slices vs known full-run deltas where available. **A proxy is trusted only if it ranks known improvements correctly.** Document correlation in [EXPERIMENTS.md](EXPERIMENTS.md).
5. **Git conventions**: every experiment = branch `exp/NNN-slug` off `main`; results recorded in ledger on `main`; merged only if it wins on proxy + survives a confirmation run at the next tier. Long-lived integration branch `next` accumulates winners between full-run validations.
6. **Geekbench 5** the VM (single-core T) so local wall-clock converts to official hours: budget_hours = 70,000/T; track `time_used/budget` for every full run.

**Exit criteria:** baseline reproduced bit-exact, ledger live, proxy tiers validated, one full enwik9 compress run completed on Azure to anchor the baseline number on our hardware.

## Phase 1 — Understand the model (parallel with Phase 0 runs)
- Deep-dive `fxcmv1.cpp`, predictor graph, mixers, PPM; finish [ARCHITECTURE.md](ARCHITECTURE.md).
- **Profile** (perf/VTune on VM): time per component; memory map. The profile drives everything in Phase 2.
- Literature pass: fx-cmix/fx2-cmix discussion threads (encode.su), Knoll's cmix docs, the fx2 changes timeline (links in README), Mahoney's DCE book + LTCB notes, starlit/phda9 article-ordering work, paq8px(d) changelogs for model ideas not yet ported.

**Exit criteria:** ARCHITECTURE.md complete; ranked hotspot list; written list of ≥20 candidate experiments with expected-value guesses.

## Phase 2 — Experiment streams (ordered by expected ROI)
Run many cheap experiments; promote winners up the tier ladder (1 MB smoke → 50/100 MB proxy → enwik8/full-tier → full enwik9 integration run).

**A. Speed first** (time budget → model capacity). fx2 used ~70% of allowed time; every saved hour funds model complexity elsewhere.
   - Profile-guided micro-opt of fxcm hot loops, hash functions, cache layout; SIMD where it doesn't break single-core rules (vector instructions are legal — only multi-threading/GPU are not).
   - PPM mmap_to_disk cost; smarter paging or memory rebalance.
   - Cheap wins: UPDATE_LIMIT / weight-update-skip thresholds.
**B. Tuning** (no new code, pure knobs): mixer learning rates, context-map sizes/allocations, hash table budgets, SSE/APM stage params, LSTM size vs time, SEED. Automatable sweeps — ideal for the harness.
**C. Model changes** (the main course, needs Phase 1 knowledge):
   - new/changed contexts in fxcm (word-type interactions, wiki-structure contexts);
   - state-table search (fx2 swapped one table for gains — there's room here);
   - match-model variants; revisit some of the 16 predictors fx2 deleted, now affordable if Phase A buys time;
   - LSTM: size/training-rate/feature changes.
**D. Preprocessing / data-side:**
   - article order: re-run embedding pipeline with a 2026-era embedding model (the order file is a precomputed input — improvements cost zero runtime);
   - dictionary: re-optimize english.dic content/ordering for the actual corpus statistics;
   - transform tweaks (entity handling, template/link markup).
**E. Size of S1:** smaller binary is byte-for-byte as valuable as better compression. Code-size diet, UPX settings, runtime-generated tables.

Decision rule per experiment: keep iff Δ(archive bytes at confirmation tier) + Δ(binary bytes) < 0 **and** time/RAM stay inside limits with margin.

## Phase 3 — Integrate & validate
- Merge accumulated winners into `next`; full enwik9 compress + decompress round-trip on reference-class VM; confirm S, time (<70,000/T h), RAM (<10 GB), disk (<100 GB).
- Repeat experiment→integrate cycles until S ≤ 109,685,196 with safety margin (aim ~109.5 MB to absorb committee-machine variance).

## Phase 4 — Submission prep (later)
Pin `-march` to committee hardware, final PGO build, source cleanup + OSI license, algorithm write-up, timing/memory dossier on a Geekbenched machine.

---

## Budget & risks
- **Azure for Students subscription** (~$100 credit typically; quotas were unregistered until 2026-06-10 — limits TBD). A 4-vCPU VM ≈ $0.17–0.20/h → full compress+decompress validation ≈ $20. Proxy experiments are cents-to-dollars. **Risk: credit exhaustion → need user to confirm budget/upgrade path.**
- Student subscriptions often cap regional vCPUs (~6) and exclude some families — may constrain VM choice (Ddv5/Dasv5 likely OK).
- 50 h runs on spot VMs risk eviction; use on-demand for full runs, spot for sweeps.
- Proxy/full-run divergence is the central methodological risk — hence Phase 0.4 validation before trusting any result.
- This code is 20 years optimized; expect many null results. The ledger must record nulls too.

## Current status (2026-06-10)
- [x] Rules + record verified; repo surveyed; plan written.
- [x] Azure providers (Compute/Network/Storage) registration kicked off.
- [ ] Phase 0.1: provision lab VM ← **next action**

# Infrastructure Notes

## Local machine
M1 Mac (ARM, darwin). **Cannot build or benchmark x86-64 submission binaries.** Used only for orchestration, docs, git, and Azure CLI.

## Azure
- Subscription: **Azure for Students** (`eb6d20b6-8925-47bd-9ebc-06307613893b`), tenant Tufts, user slupo01@tufts.edu.
- 2026-06-10: Microsoft.Compute/Network/Storage providers were NotRegistered; registration submitted. Check with `az provider show -n Microsoft.Compute --query registrationState`.
- Quotas unknown until registration completes: `az vm list-usage --location eastus -o table`. Student subs typically allow ~6 vCPUs/region, B/Dv5/Dasv5 families.

### VM selection rationale
The prize time budget is 70,000/T hours (T = Geekbench 5 single-core). Faster single-core ⇒ shorter wall-clock but proportionally smaller budget, so the ratio is roughly hardware-neutral; what matters is:
1. **x86-64** (match committee machines; fx2 was tuned on Cascade Lake, T=1026).
2. Strong, *consistent* single-core (no burstable B-series for timing runs).
3. ≥16 GB RAM (10 GB working set + OS headroom), ~64 GB disk (enwik9 + temp ~21 GB).

Preferred: **D4ds_v5 / D4as_v5 / F4s_v2** (4 vCPU, 16 GB) — run experiments pinned to one core (`taskset -c 0`). Spot for sweeps, on-demand for long validation runs.

### Standard provisioning (Phase 0.1, to be scripted in `infra/`)
- Ubuntu 22.04 LTS Gen2 image, SSH key auth, auto-shutdown tag for idle protection.
- Setup: `install_tools/install_clang-17.sh`, `install_tools/install_upx.sh`, make, git, perf (`linux-tools`), Geekbench 5 CLI.
- enwik9 fetched once (`enwik9.zip`, ~300 MB) onto a persistent data disk or re-downloaded per VM.
- Every result row in the ledger records VM size + region + kernel, so numbers are never compared across unlike machines silently.

### Cost model (East US, on-demand, approx)
| Item | Cost |
|---|---|
| D4ds_v5 | ~$0.19/h → 24 h ≈ $4.6 |
| Full compress run (~50 h) | ~$10 |
| Full round-trip validation | ~$20 |
| 100 MB proxy run (est. ~5 h, TBD) | ~$1 |
| 1 MB smoke (~4 min) | pennies |

**Open question for user:** remaining credit on the student subscription and willingness to fund beyond it (~$100 doesn't survive many full validation runs).

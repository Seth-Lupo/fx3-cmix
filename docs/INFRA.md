# Infrastructure Notes

## Local machine
M1 Mac (ARM, darwin). **Cannot build or benchmark x86-64 submission binaries.** Used only for orchestration, docs, git, and Azure CLI.

## Current VMs (2026-06-11)
| VM | IP | Size | Role |
|---|---|---|---|
| lab1 | 20.29.69.113 | D4ds_v4 on-demand | core0: enwik9 baseline anchor (→~Jun13); core3: v26 standalone 586MB RT (/mnt/work/v26full); /mnt/work/proxy has all slices + full streams |
| exp1 | 130.131.243.31 | E2s_v3 on-demand | experiment lane, SINGLE-TENANT for 25-step builds (~8GB RSS); auto-shutdown DISABLED 2026-06-11 for overnight T2 A/B (re-enable when done: `az vm auto-shutdown -g hutter-lab -n exp1 --time 0900`) |
| spot2 | 20.29.114.158 | E2s_v3 spot | T0/T1 probe lane (eviction-tolerant queue at /mnt/work/probe_queue.sh, ledger-skip restart) |

spot1 deleted 2026-06-11 (3 evictions; user approved on-demand swap). SSH user `hutter`, key ~/.ssh/id_ed25519; lab1's pubkey is in exp1's authorized_keys for direct scp (spot2 has no lab1 trust — relay small files via the Mac: `ssh lab1 'cat f' | ssh spot2 'cat > f'`, verify md5). Eviction/rebuild routine: provision.sh + setup.sh SKIP_ENWIK9=1 + copy slices from lab1.

**Gotchas (cost real time):** (1) Public-IP quota is 3 and deleting a VM does NOT delete its public IP — `az network public-ip list -g hutter-lab` and delete orphans, else `az vm create` fails with the masked "content already consumed" CLI error (rerun with `--debug` to see the real ARM preflight error). (2) Spot quota is 3 low-priority vCPUs total → spot boxes must be 2-core (E2s_v3 works; 16GB fits the ~8GB tip RSS).

## Azure
- Subscription: **Azure for Students** (`eb6d20b6-8925-47bd-9ebc-06307613893b`), tenant Tufts, user slupo01@tufts.edu.
- 2026-06-10: Microsoft.Compute/Network/Storage providers registered.
- **Quotas (eastus, confirmed 2026-06-10):** 6 regional vCPUs total; 4 vCPUs per family for Dv4/Ddv4/Dasv4/Ddsv4/Dv3/Fsv2 etc. **All v5+ families are quota 0.** Burstable Bsv2/Basv2 have 10 (timing-unreliable; non-timing utility work only).

### VM selection rationale
The prize time budget is 70,000/T hours (T = Geekbench 5 single-core). Faster single-core ⇒ shorter wall-clock but proportionally smaller budget, so the ratio is roughly hardware-neutral; what matters is:
1. **x86-64** (match committee machines; fx2 was tuned on Cascade Lake, T=1026).
2. Strong, *consistent* single-core (no burstable B-series for timing runs).
3. ≥16 GB RAM (10 GB working set + OS headroom), ~64 GB disk (enwik9 + temp ~21 GB).

Chosen within quota: **Standard_D4ds_v4** (4 vCPU, 16 GB RAM, 150 GiB local temp SSD — Cascade Lake, the same platform generation as fx2's reference c2-standard-4). F4s_v2 rejected: only 8 GB RAM. Run experiments pinned to one core (`taskset -c 0`). Spot (3 low-priority vCPU quota) for sweeps where eviction is tolerable; on-demand for long validation runs.

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

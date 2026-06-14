# AINL Lab Additions to sionna-rk

Work done by our lab (**AINL**) on top of **NVlabs/sionna-rk v1.2.0 (`fa405b8`)**.

This file is **fork-only** and is intentionally kept separate from the upstream
`README.md`, so syncing with upstream (`git merge upstream/main`) never conflicts
with it. Anything listed here is added/changed by us; upstream files are otherwise
left untouched.

> Regenerate the file list any time with:
> `git diff --stat fa405b8..ainl-dev`  (changed files)
> `git log --oneline fa405b8..ainl-dev`  (our commits)

## Added tools

- **[scripts/channel_sweep.sh](scripts/channel_sweep.sh)** — Sweep an OAI
  rfsimulator (`chanmod`) channel parameter over a list of values and record
  iperf3 throughput per step.
  - Default parameter is **path loss (`ploss`)**. Note: in the rfsimulator
    `ploss` is applied as a *gain* (`10^(ploss/20)`), so **negative = attenuation
    (farther), positive = amplification** (clips the int16 samples above ~+20 dB).
    Approx in-sim SNR: `SNR_dB ≈ ploss − 2·noise_power_dB`.
  - Default sweep `10,5,0,-5,-10` starts at the safe throughput peak (+10 dB) and
    fades the link down, modelling a UE moving away from the cell.
  - Controls the channel via the rfsimulator telnet server (DL = model 0 on the
    UE, UL = model 1 on the gNB), uses a warm-up burst + `iperf3 -O 2` for
    steady-state numbers, and restores the best-throughput value on exit.
  - Usage: `./scripts/channel_sweep.sh -h`

- **[scripts/start_ue.sh](scripts/start_ue.sh)** — Start/restart **only** the
  soft-UE container (leaving the 5G core and gNB running) and wait for the UE to
  attach (`oaitun_ue1`). Useful because the rfsim UE in this build aborts
  intermittently (`buffer overflow detected`) and needs to be brought back up.
  - Usage: `./scripts/start_ue.sh [rfsim|b200]`

## Change log

| Commit | Summary |
|--------|---------|
| `395658a` | channel_sweep: realistic path-loss sweep (ploss as gain) + robustness |
| `02b1ae2` | channel_sweep: label results column by sweep direction (DL/UL) |
| `7f6a1e9` | Add rfsim channel-sweep and UE-only start scripts |

## Repo / branch layout

- `origin`   → `sunghyunc7/ainl-sionna-rk` (our fork; default push/pull target)
- `upstream` → `NVlabs/sionna-rk` (pull updates only)
- `main`     → mirrors `upstream/main` (kept clean for syncing)
- `ainl-dev` → our working branch (all lab work lives here)

### Syncing with upstream

```bash
git fetch upstream
git switch main && git merge upstream/main && git push
git switch ainl-dev && git merge main
```

# AINL Lab Additions to sionna-rk

Work done by our lab (**AINL**) on top of **NVlabs/sionna-rk v1.2.0 (`fa405b8`)**.

This file is **fork-only** and is intentionally kept separate from the upstream
`README.md`, so syncing with upstream (`git merge upstream/main`) never conflicts
with it. Anything listed here is added/changed by us; upstream files are otherwise
left untouched.

## Changed files

The list below is **auto-generated** by `scripts/update-ainl.sh` (run from the
`pre-commit` git hook), comparing the working state to the NVlabs base `fa405b8`.
Do not edit it by hand — anything between the AUTO markers is overwritten.

<!-- AUTO:files start -->
- `scripts/channel_sweep.sh` — added
- `scripts/hooks/pre-commit` — added
- `scripts/start_ue.sh` — added
- `scripts/update-ainl.sh` — added
- `scripts/watch_MCS.sh` — added
<!-- AUTO:files end -->

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

- **[scripts/watch_MCS.sh](scripts/watch_MCS.sh)** — Follow the gNB log and show
  the link-quality metrics that actually respond to channel changes (OAI prints
  no steady "SNR dB" stream): per-UE **DL MCS/BLER** and **UL MCS/SNR/BLER**.
  Each line is prefixed with the current channel value read from
  `channel_sweep.sh`'s state file, so you can line up `ploss=N` against the link
  response. The `ue` mode instead reads the UE log (harq / code rate /
  bit-symbol). Pairs with `channel_sweep.sh`; MCS only moves while traffic flows.
  - Usage: `./scripts/watch_MCS.sh [dl|ul|ue]`  (no arg = both directions)

- **[scripts/update-ainl.sh](scripts/update-ainl.sh)** — Regenerate the
  "Changed files" region above from git. Run automatically by the `pre-commit`
  hook; can also be run by hand. After a fresh clone, install the hook once:
  `cp scripts/hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`

## Local environment tweaks (not tracked)

These live under `config/`, which is **local and untracked** (the repo ignores
`.env`; the dir is generated/per-machine). Re-apply them after a fresh clone or
after regenerating configs:

- **UE/gNB auto-restart** — in `config/common/docker-compose.yaml`, add
  `restart: unless-stopped` to both the `oai-gnb` and `oai-nr-ue` services. The
  rfsim softmodems abort intermittently (`buffer overflow detected`) on
  channelmod activity; this makes them self-heal (docker auto-restarts and the
  UE re-attaches within a few seconds) instead of staying dead and needing a
  manual `./scripts/start_ue.sh`. To apply to already-running containers without
  recreating them:

  ```bash
  docker update --restart unless-stopped oai-gnb oai-nr-ue
  ```

  Note: this is self-healing, not a fix — a sweep can still lose its remaining
  steps if a softmodem dies mid-run. A real fix needs an OAI image rebuild.

## Change log

This table is curated by hand (kept current as lab work lands); the file list
above is auto-generated. For the raw history: `git log --oneline fa405b8..ainl-dev`.

| Commit | Summary |
|--------|---------|
| `43cf196` | watch_MCS: select metrics by direction (dl/ul/ue) |
| `7fbefad` | Add scripts/watch_MCS.sh — live MCS/SNR/BLER monitor |
| `ab9f7c2` | channel_sweep: shorten per-step time so ploss changes ~2x more often |
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

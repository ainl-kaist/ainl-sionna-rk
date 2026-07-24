# AINL Lab Additions to sionna-rk

Work done by our lab (**AINL**) on top of **NVlabs/sionna-rk v1.2.0 (`fa405b8`)**.

This file is **fork-only** and is intentionally kept separate from the upstream
`README.md`, so syncing with upstream (`git merge upstream/main`) never conflicts
with it. Anything listed here is added/changed by us; upstream files are otherwise
left untouched.

> **Label convention:** notes tagged **`[SH]`** are personal records left by
> Sunghyun (lab lead) — so students and collaborators can tell them apart from
> general project documentation.

## Changed files

The list below is **auto-generated** by `scripts/update-ainl.sh` (run from the
`pre-commit` git hook), comparing the working state to the NVlabs base `fa405b8`.
Do not edit it by hand — anything between the AUTO markers is overwritten.

<!-- AUTO:files start -->
- `.claude/settings.json` — added
- `.gitignore` — modified
- `config/b200/.env` — added
- `config/common/docker-compose.override.yaml` — added
- `config/common/docker-compose.yaml` — added
- `config/common/flexric.conf` — added
- `config/common/gnb.sa.band78.106prbs.conf` — added
- `config/common/gnb.sa.band78.24prbs.conf` — added
- `config/common/gnb.sa.band78.51prbs.conf` — added
- `config/common/mini_nonrf_config.yaml` — added
- `config/common/mysql-healthcheck.sh` — added
- `config/common/nrue.uicc.conf` — added
- `config/common/oai_db.sql` — added
- `config/common/sys_config.yaml` — added
- `config/rfsim-ho/.env` — added
- `config/rfsim-ho/.gitignore` — added
- `config/rfsim-ho/README.md` — added
- `config/rfsim-ho/docker-compose.yaml` — added
- `config/rfsim-ho/gnb-cu.conf` — added
- `config/rfsim-ho/gnb-du.conf` — added
- `config/rfsim-ho/neighbour-config.conf` — added
- `config/rfsim-ho/nrue.uicc.conf` — added
- `config/rfsim-ho/start_handover.sh` — added
- `config/rfsim/.env` — added
- `config/testing/.env` — added
- `flexric-disk-growth-rootcause.md` — added
- `patches/flexric.patch` — added
- `patches/openairinterface5g.patch` — modified
- `scripts/README.md` — added
- `scripts/channel_sweep.sh` — added
- `scripts/configure-system.dgx-spark.sh` — modified
- `scripts/configure-system.sh` — modified
- `scripts/hooks/pre-commit` — added
- `scripts/quickstart-oai.sh` — modified
- `scripts/restart_ue.sh` — added
- `scripts/start_ue.sh` — added
- `scripts/start_ues.sh` — added
- `scripts/stop_ue.sh` — added
- `scripts/stop_ues.sh` — added
- `scripts/switch_env.sh` — added
- `scripts/update-ainl.sh` — added
- `scripts/watch_MCS.sh` — added
- `uhd` — added
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

- **[scripts/stop_ue.sh](scripts/stop_ue.sh)** — Counterpart to `start_ue.sh`:
  `docker compose stop` the primary UE only (core + gNB stay up). Uses `stop`
  (not `down`) so it can be restarted; the `restart: unless-stopped` policy
  honours a manual stop, so the UE won't auto-restart until `start_ue.sh`.
  - Usage: `./scripts/stop_ue.sh [rfsim|b200]`

- **[scripts/restart_ue.sh](scripts/restart_ue.sh)** — Thin wrapper that runs
  `stop_ue.sh` then `start_ue.sh` for the primary UE only (core + gNB stay up),
  for a clean detach/reattach without restarting the whole system. Useful after
  the rfsim UE aborts or after a channel-model change that needs a fresh attach.
  - Usage: `./scripts/restart_ue.sh [rfsim|b200]`

- **[scripts/start_ues.sh](scripts/start_ues.sh)** — Attach **multiple UEs** to
  the same gNB at once (rfsim). Starts EXTRA UEs (`oai-nr-ue2`, `oai-nr-ue3`, …)
  alongside the primary `oai-nr-ue`, each with its own container name, public_net
  IP (`.151`, `.152`, …), provisioned IMSI (the spares already in
  `oai_db.sql`: `…001101`, `…016069`), and CPU thread-pool (offset off the
  primary's cores). The OAI rfsim server accepts up to 250 clients (broadcasts DL
  to each, sums UL), so multiple full-stack UEs work against one gNB. Per-UE
  configs are rendered from `nrue.uicc.conf` into `config/common/generated/`
  (only the IMSI differs; key/opc are shared). Capped at the number of spare
  IMSIs (2); add subscribers to `oai_db.sql` to go higher.
  - Usage: `./scripts/start_ues.sh [-n <count>] [rfsim]`  (default 2 extra UEs)

- **[scripts/stop_ues.sh](scripts/stop_ues.sh)** — Remove the extra UEs started
  by `start_ues.sh` (every `oai-nr-ue<N>` for N≥2); leaves the primary UE alone.
  - Usage: `./scripts/stop_ues.sh`

- **[scripts/watch_MCS.sh](scripts/watch_MCS.sh)** — Follow the gNB log and show
  the link-quality metrics that actually respond to channel changes (OAI prints
  no steady "SNR dB" stream): per-UE **DL MCS/BLER** and **UL MCS/SNR/BLER**.
  Each line is prefixed with **(1)** the OAI log timestamp (the per-UE stat lines
  carry no timestamp of their own, so it's tracked from the block header line)
  and **(2)** the current channel value: `ploss=N` from `channel_sweep.sh`'s
  state file while a sweep runs, else the live path-loss read straight from the
  rfsimulator telnet (a background poller that backs off whenever a sweep owns
  the single-client telnet). So you can line up `ploss=N` against the link
  response even with no sweep running. The `ue` mode instead reads the UE log
  (harq / code rate / bit-symbol). Pairs with `channel_sweep.sh`; MCS only moves
  while traffic flows.
  - Usage: `./scripts/watch_MCS.sh [dl|ul|ue]`  (no arg = both directions)

- **[scripts/update-ainl.sh](scripts/update-ainl.sh)** — Regenerate the
  "Changed files" region above from git. Run automatically by the `pre-commit`
  hook; can also be run by hand. After a fresh clone, install the hook once:
  `cp scripts/hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`

## Environment tweaks (in `config/`)

These live under `config/` (now tracked). The only thing excluded is the
transient `config/common/generated/` (per-UE configs rendered by
`start_ues.sh`), which is git-ignored. To apply the tweaks below to
already-running containers without recreating them, use the `docker update` /
`docker compose up` commands noted:

- **UE/gNB auto-restart** — in `config/common/docker-compose.yaml`,
  `restart: unless-stopped` on both the `oai-gnb` and `oai-nr-ue` services. The
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

- **`SYS_PTRACE` on UE/gNB** — also in `config/common/docker-compose.yaml`,
  `SYS_PTRACE` was added to the `oai-nr-ue` and `oai-gnb` `cap_add` lists so
  `gdb` can attach inside the (unprivileged) containers to debug the
  `buffer overflow detected` abort. The prebuilt binaries ship with full debug
  symbols and OAI deliberately leaves `SIGABRT`/`SIGSEGV` at default (the handler
  in `softmodem-common.c` is `#if 0`-ed, to allow core dumps), so a `gdb`
  backtrace gives file:line directly — no ASan rebuild needed for a first trace.

## FlexRIC source patches (`patches/flexric.patch`)

FlexRIC ships two writers that grow **without bound** on the container writable
layer and silently fill the host disk (root-caused in
[flexric-disk-growth-rootcause.md](flexric-disk-growth-rootcause.md); on
`ainl-spark-02` these two files reached ~1.1 TB combined). `flexric` is a
*nested* submodule (`ext/openairinterface5g/openair2/E2AP/flexric`, pinned by
SHA), so it is **not** covered by `patches/openairinterface5g.patch`. The fix
lives in a separate `patches/flexric.patch`, applied from within the flexric
submodule by `scripts/quickstart-oai.sh` right after `git submodule update`
(idempotent), and picked up by the build via
`docker/Dockerfile.flexric.ubuntu` (`COPY openair2/E2AP/flexric`).

- **RIC `/log.txt` (nearRT-RIC)** — `src/ric/iApps/stdout.c` dumped every
  MAC/RLC/PDCP indication to `log.txt` (cwd `/`) with no rotation (observed
  ~888 GB). The patch defaults `file_path` to `/dev/null`; set
  **`FLEXRIC_IAPP_LOG=<path>`** to re-enable file logging.
- **xApp sqlite DB (monitor_xapp)** — `src/xApp/msg_handler_xapp.c` INSERTed
  every E2 indication into `/tmp/xapp_db_<us>` forever (~24 GB/day, observed
  ~197 GB). Our xApps stream over ZMQ and never read this DB, so the patch skips
  `write_db_xapp` by default; set **`FLEXRIC_XAPP_DB=1`** to restore it.

Rebuild to apply: `./scripts/build-oai-images.sh <ext/openairinterface5g>`
(rebuilds `oai-flexric:latest`), then recreate `nearRT-RIC` / `monitor_xapp` on
each host. After a fresh `quickstart-oai.sh` the patch is applied automatically.

## Change log

This table is curated by hand (kept current as lab work lands); the file list
above is auto-generated. For the raw history: `git log --oneline fa405b8..ainl-dev`.

| Commit | Summary |
|--------|---------|
| `7687a27` | restart_ue.sh; watch_MCS: log-timestamp prefix + live ploss fallback |
| `2a59c8b` | Track config/ (lab configs, compose, subscriber DB) |
| `da0f698` | Add multi-UE rfsim scripts (start_ues/stop_ues) + stop_ue |
| `83c89c7` | channel_sweep: state-file handoff + restore channel on interrupt |
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

### Dev machines  `[SH]`

Lab work happens on more than one host; they share state only through
`origin/ainl-dev`, so **always `git pull` before starting and `git push` when
done** to avoid diverging branches.

- **`ainl-spark-01`** — primary development host (as of 2026-06).
- **`ainl-spark-02`** — used mainly by a student for their own development.
  (Earlier lab work up to `5ff39e3` was done here before the move to
  `ainl-spark-01`.)

Claude Code settings: the shared `.claude/settings.json` (curated allowlist) is
committed so everyone inherits it; personal/host-specific overrides go in
`.claude/settings.local.json`, which is git-ignored.

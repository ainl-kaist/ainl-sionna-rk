# scripts/

**English** | [한국어](README.ko.md)

Helper scripts for the Sionna-RK / OAI stack, grouped by area. The order roughly
follows the lifecycle (host setup → image build → running the system →
experiments), with developer / version-tracking helpers at the end.

Many runtime scripts take a **config profile** argument that selects which
`config/<profile>/.env` to read (default `rfsim`). Valid profiles: `rfsim`
(software RF simulator), `b200` (real USRP B200 radio).

Some scripts are wrapped by top-level `make` targets — `make prepare-system`
(host setup), `make sionna-rk` (fetch OAI + build + configs + plugins),
`make build-gnb` (RAN images).

## Contents
1. [Host setup & installation](#1-host-setup--installation)
2. [Fetching sources, patching & building images](#2-fetching-sources-patching--building-images)
3. [Runtime — system lifecycle](#3-runtime--system-lifecycle)
4. [Runtime — UE control](#4-runtime--ue-control)
5. [Runtime — GPU MPS](#5-runtime--gpu-mps)
6. [Runtime — switching environments](#6-runtime--switching-environments)
7. [Experiments, demos & monitoring](#7-experiments-demos--monitoring)
8. [Developer / version-tracking helpers](#8-developer--version-tracking-helpers)

---

## 1. Host setup & installation

One-time setup per machine (Jetson / Grace-class hosts). Wrapped by
`make prepare-system`. Some steps need `sudo`.

- **`detect_host.sh`** — Detects the platform from board information (e.g. "Orin
  Nano Super", "AGX Orin", "DGX Spark"). Other scripts use it to pick
  platform-specific settings.
- **`configure-system.sh`** — Applies host settings. Dispatches to the matching
  **`configure-system.<platform>.sh`** (`agx-orin`, `agx-thor`, `dgx-spark`,
  `orin-nano`). Flags: `--force-platform <p>`, `--verbose`, `--dry-run`.
- **`build-custom-kernel.sh`** — Builds a custom L4T kernel (needed for real-time
  operation / USRP). `<destination_path>`, `--l4t-version`, `--clean`,
  `--dry-run`, etc. Needs `sudo`.
- **`install-custom-kernel.sh`** — Installs the built kernel + modules and updates
  the boot sequence. Needs `sudo`.
- **`install-usrp.sh`** — Installs the UHD/USRP drivers (for the `b200` profile).
  `--branch <branch|tag>`, `--force`, `--dry-run`.

## 2. Fetching sources, patching & building images

Fetches upstream OAI, applies this kit's patches and builds the docker images.
Wrapped by `make sionna-rk` and `make build-gnb`.

- **`quickstart-oai.sh`** — RAN end to end: fetches, patches and builds a pinned
  OAI version. `--source <kit-rootdir> --dest <oai5g_dir>`, `--oai-version`,
  `--no-build`, `--clean`, `--debug`, `--tag`.
- **`quickstart-cn5g.sh`** — Does the same for the OAI CN5G core.
  `--arch (x86|arm64)`, `--branch`, `--source`, `--dest`, etc.
- **`patch-oai.sh`** — Applies this kit's source changes to the OAI RAN tree (used
  inside quickstart-oai).
- **`patch-oai-cn5g.sh`** — Applies the patches to the CN5G tree.
- **`generate-configs.sh`** — Generates the `config/` tree: shared files go to
  `config/common`, compose/env files to `config/<name>`, and per-config patches
  are applied.
- **`build-oai-images.sh`** — Builds the CUDA RAN images (`ran-base-cuda` →
  `ran-build-cuda` → `oai-gnb-cuda`, `oai-nr-ue-cuda`, `oai-flexric`).
  `<oai5g_dir>`, `--debug`, `--tag`, `--no-cache`, `--force-platform`.
- **`build-cn5g-images.sh`** — Builds the CN5G core images. `<oai-cn5g_dir>`,
  `--tag`, `--debug`.
- **`show_build_errors.sh`** — Scans `build.log` and prints the compile errors (for
  a quick diagnosis after a failed build).

## 3. Runtime — system lifecycle

Brings the whole single-gNB stack up and down.

- **`start_system.sh [rfsim|b200|ho]`** — For `rfsim`/`b200`, starts the whole single-gNB stack: the 5G core (`mysql`,
  `oai-amf`, `oai-smf`, `oai-upf`, `oai-ext-dn`), `nearRT-RIC`, `oai-gnb`, the
  primary `oai-nr-ue`, and `monitor_xapp`. Waits until each container is healthy.
  Default profile `rfsim`. `ho` delegates to the rfsim-based CU+2×DU handover
  stack (`config/rfsim-ho/start_handover.sh up`). When starting `rfsim`/`b200`
  with the handover stack still up, it brings that down first and switches to the
  single gNB. This is the usual entry point.
- **`stop_system.sh`** — Runs `docker compose down` on both the single-gNB stack
  (`config/common`) and the handover stack (`config/rfsim-ho`). Removes the
  containers **and the shared network**. No arguments.

> **Two environments.** The single-gNB stack (`config/common`) and the CU+2×DU
> handover stack (`config/rfsim-ho`, see §6) share the same network
> (`oai-public-net`) and container names, so **only one runs at a time**. Bring
> one down before starting the other. The monitoring stack is on a separate
> network and is not affected.

## 4. Runtime — UE control

Manages only the UEs, leaving the core + gNB running.

- **`start_ue.sh [rfsim|b200]`** — (Re)starts only the primary `oai-nr-ue`. Waits
  until it is healthy and the tunnel (`oaitun_ue1`) has an IP, so on success it is
  ready for traffic right away. Warns if `oai-gnb` is not running.
- **`stop_ue.sh [rfsim|b200]`** — Stops only the primary UE with
  `docker compose stop` (not `down`). The container is kept, and this overrides
  the `restart: unless-stopped` policy, so it will not restart on its own until
  you start it again.
- **`restart_ue.sh [rfsim|b200]`** — `stop_ue.sh` then `start_ue.sh`; a clean
  detach/reattach. Useful after the rfsim UE aborts or after changing the channel.
- **`start_ues.sh [-n <count>] [rfsim|b200]`** — Starts **extra** soft-UEs
  (`oai-nr-ue2`, `oai-nr-ue3`, …) on the same gNB. Each has its own name, IP
  (`192.168.71.151`, …), provisioned IMSI and thread pool. `-n` defaults to 2
  and is capped by the number of spare IMSIs in `config/common/oai_db.sql`. The
  primary UE is left alone. (These are plain `docker run` containers, not
  compose services.)
- **`stop_ues.sh`** — Removes all extra UEs (`oai-nr-ue<N>`, N ≥ 2) and keeps the
  primary UE and the rest of the system. `stop_system.sh` does **not** remove
  them, so run this first when cleaning up or switching.

## 5. Runtime — GPU MPS

CUDA Multi-Process Service. Lets the gNB PHY and the Sionna RT GUI share the GPU.
(The compose files reference it through the `CUDA_MPS_*` environment variables.)

- **`start_mps.sh`** — Starts the MPS control daemon.
- **`stop_mps.sh`** — Stops it.

## 6. Runtime — switching environments

- **`switch_env.sh`** — Switches between the single-gNB and handover environments.
  Fully brings down the *other* one (including extra UEs) and brings up the one
  requested — enforcing the "one at a time" rule automatically.

  ```bash
  ./scripts/switch_env.sh ho              # -> handover stack (CU + 2x DU)
  ./scripts/switch_env.sh single          # -> single gNB, rfsim (default)
  ./scripts/switch_env.sh single b200     # -> single gNB, b200 profile
  ./scripts/switch_env.sh status          # which environment is currently up
  ./scripts/switch_env.sh down            # bring both down (idle)
  ```

  Under the hood: `single` → `start_handover.sh down` then
  `start_system.sh <profile>`; `ho` → `stop_ues.sh` + `stop_system.sh` then
  `start_handover.sh up`.

  The handover stack itself is driven by **`config/rfsim-ho/start_handover.sh
  {up|ho|status|watch|down}`** (`ho` triggers one F1 handover). See
  `config/rfsim-ho/README.md` for the full description.

## 7. Experiments, demos & monitoring

- **`install-ue-wwan-status.sh`** — Installs the `ue-wwan-status` command for all users on the UE device (Jetson).
  The source lives only in this repository; run this **from the checkout on the gNB host**. It sends a
  commit-stamped copy to the UE host with `scp` and installs it as `/usr/local/bin/ue-wwan-status`, owned by root, mode 0755.

  ```bash
  ./scripts/install-ue-wwan-status.sh                       # default: ainl_jon@100.77.54.30
  ./scripts/install-ue-wwan-status.sh --host USER@HOST      # or UE_WWAN_HOST=USER@HOST
  ssh ainl_jon@100.77.54.30 ue-wwan-status --version        # check the installed commit
  ```

  It reuses a single ssh connection, so it asks for the UE login password once, then for the UE host's sudo
  password. Run without a terminal, it only copies the file, prints the command to run there, and stops with
  exit code 3. After installing, it fails if `--version` differs from this checkout's commit.
  Staged changes are also marked `-dirty`, so commit and rerun from a clean tree to update. `--prefix DIR`
  installs into `DIR/bin` on this machine. The UE host needs Python 3, iproute2, and a ping allowed to send
  ICMP; the installer does not change networking or ping permissions.

- **`ue_wwan_status.py`** — WWAN diagnostics run **on the UE device's Linux host**.
  Checks that the default interface `wwan0` exists, its UP flag, global IP, and IPv4/IPv6 routes.
  It does not fail just because a cellular interface reports `operstate UNKNOWN`.
  Needs Python 3, iproute2 and ping. Output is in English.
  The screen output has a KST timestamp and ruled sections `INTERFACE AND IP ADDRESS`, `ROUTING`,
  `IP CONNECTIVITY` and `RESULT SUMMARY`. It shows only the check results and key explanations,
  and distinguishes a failed general route lookup from a successful interface-bound ping.
  JSON timestamps keep the existing UTC format.

  ```bash
  # copy this file to the UE device, then run it there
  ./ue_wwan_status.py                           # check the default server 192.168.72.135
  ./ue_wwan_status.py --target <reachable-IP>    # change the server
  ./ue_wwan_status.py --watch
  ./ue_wwan_status.py --json
  ./ue_wwan_status.py --interface wwan1
  ./ue_wwan_status.py --local-only              # skip the connectivity check
  ```

  For `<reachable-IP>`, use the real numeric IP of a server the UE should be able to reach.
  The default server is `192.168.72.135`; change it with `--target`.
  It checks whether the route for general traffic picks the WWAN interface,
  and separately checks connectivity through that interface with `ping -I wwan0`.
  `--local-only` checks only the local configuration and does not mean connectivity works.
  A missing default route is informational, since per-destination routes can still carry traffic.
  Route checks under policy routing reflect general traffic from the current user and do not
  emulate per-app marks and the like. Ping can also fail because ICMP is blocked.
  It changes no settings. If you get a ping permission error, check the device's ping permissions.
  Exit codes: 0 (checks passed), 1 (checks failed), 2 (tool/runtime error).
  `--watch` runs until Ctrl+C, and `--json --watch` prints one JSON object per line.


- **`install-ue-status.sh`** — Installs the `ue-status` command for all users.
  So that it does not depend on repository access, it copies `ue_status.py` to
  `/usr/local/bin/ue-status` and makes it executable (0755). With the default path it is owned by root.

  ```bash
  sudo ./scripts/install-ue-status.sh
  ue-status
  ```

  After editing the source script, rerun the installer to update it.
  `--prefix DIR` changes the install location to `DIR/bin/ue-status`.
  The install directory must be on each user's PATH, and running it needs Python 3, the Docker CLI and
  access to the Docker daemon. The installer does not change Docker permissions or groups.

- **`ue_status.py`** — Prints a table of the latest MAC statistics for each UE recently seen in the gNB log.
  Needs only the Python 3 standard library and the Docker CLI; output and help are in English.
  Shows RNTI, CU-UE-ID, IMSI, UE-IP, sync state, RSRP, UL SNR, DL/UL MCS·BLER, and cumulative TX/RX.
  The default container is `oai-gnb` and the lookup window is the last 10 seconds. Because it is log-based, a
  detached UE can linger for up to one window, and missing statistics do not prove a UE is disconnected.
  IMSI and UE-IP are looked up by linking CU-ID → RAN UE NGAP ID → IMSI across the AMF's recent UE table and the
  SMF's retained session logs. UE-IP is the address assigned to the UE's PDU session, not the Docker container
  IP. Setups with a single gNB connected to the AMF are supported; with several gNBs, duplicate identifiers or
  no record, it does not guess the IP and shows `-`.
  If the core lookup fails, it still prints the radio statistics and shows a warning in English.
  By default it sends 3 ICMP pings per UE IP from `oai-ext-dn` on every lookup (1 s reply timeout).
  It shows the raw ping output, including per-reply RTT, packet loss and RTT statistics.
  `IP CONNECTIVITY` shows the result as `REACHABLE`, `NO-REPLY`, `ERROR` or `SKIPPED`.
  No reply can be caused by blocked ICMP, so it does not conclude the connection is gone.
  Skip it with `--no-ping`, or choose the source container with `--ping-container NAME`.
  The container needs ping, and with many UEs the sequential checks can slow down refreshes.
  JSON gains `ping_container` and a per-UE list of `connectivity` results.
  SMF logs are a record of past allocations, so they do not confirm live session state; the time of the
  allocation record is shown too. If log rotation removes the record, the IP cannot be looked up.
  Watch mode also reads the retained SMF logs each time, so refreshes can be slow when the logs are large.
  Because the AMF table updates with a delay, matching info can show up late right after a reattach.

  ```bash
  ./scripts/ue_status.py                         # one lookup
  ./scripts/ue_status.py --watch                 # refresh every 2 s, Ctrl+C to quit
  ./scripts/ue_status.py --watch --interval 5    # refresh every 5 s
  ./scripts/ue_status.py -c oai-gnb --window 20  # set container and lookup window
  ./scripts/ue_status.py --json                  # JSON for automation
  ./scripts/ue_status.py --amf oai-amf --smf oai-smf  # set core containers
  ```

  `--json --watch` prints one JSON snapshot per line. `last_seen` is the UTC time from the Docker
  log, and TX/RX are cumulative bytes from the gNB's point of view. `--json` also includes PH, PCMAX,
  cumulative DL/UL error counts and HARQ rounds when they appear in the log.
  The IP-related JSON fields are `imsi`, `ue_ip`, `ip_source` and `ip_last_seen`; unknown values are `null`.

- **`channel_sweep.sh`** — Sweeps an rfsim `chanmod` parameter (e.g. path loss). For
  each value it sends `channelmod modify …` over the rfsimulator telnet (via the UE
  for DL, the gNB for UL), runs a short iperf3, and prints a throughput table.
- **`start_channel_emulation_demo.sh`** — End-to-end channel emulation demo: brings
  up the network with the CUDA channel emulator (ZMQ CIR source), waits for the UE
  to attach, runs iperf3, and launches the Sionna RT GUI with MPS. Needs the built
  images + the Sionna RT GUI installed.
- **`watch_MCS.sh`** — Follows the OAI logs and shows the link-quality metrics that
  actually respond to channel changes (per-UE DL/UL MCS, BLER, SNR from the NR_MAC
  stats; HARQ / code rate on the UE side). Pairs well with `channel_sweep.sh`.

## 8. Developer / version-tracking helpers

Shows what this kit changes relative to upstream OAI and maintains the change
manifest. Used mostly by CI and git hooks.

- **`get-oai-commit-versions.sh`** / **`get-oai-cn5g-commit-versions.sh`** — Print
  the pinned upstream commit/version of the RAN / CN5G sources.
- **`get-oai-changed-files.sh`** / **`get-oai-cn5g-changed-files.sh`** — List the
  files this kit modifies relative to the upstream base.
- **`get-config-changes.sh`** — Shows the changes in the generated configs.
- **`update-ainl.sh`** — Regenerates the auto-maintained "Changed files" region of
  `AINL.md` from git (relative to the NVlabs base commit `AINL_BASE`). Run by the
  pre-commit hook.
- **`check-readme-sync.sh`** — Checks that this folder's `README.md` (English) and
  `README.ko.md` (Korean) have the same structure: heading counts per level, the
  order of script entries, and the commands in code blocks (comments excluded). It
  does not judge translation quality. When either README is staged, the
  pre-commit hook runs it on the staged content and blocks the commit if they
  differ; it checks the repo-root `AINL.md` / `AINL.ko.md` pair the same way.
  With no arguments it compares the two files in the working tree.

---

## Typical workflows

Single gNB with 2 extra UEs, then a UE restart:

```bash
./scripts/start_system.sh rfsim       # core + gNB + primary UE
./scripts/start_system.sh ho          # core + CU + 2xDU + primary UE
./scripts/start_ues.sh -n 2           # add oai-nr-ue2, oai-nr-ue3
./scripts/restart_ue.sh               # restart the primary UE
./scripts/stop_ues.sh                 # remove the extra UEs
./scripts/stop_system.sh              # shut everything down
```

Switch to handover, run one handover, and switch back:

```bash
./scripts/switch_env.sh ho
cd config/rfsim-ho && ./start_handover.sh status   # UE on DU0
./start_handover.sh ho                              # UE -> DU1
cd ../.. && ./scripts/switch_env.sh single          # back to single gNB
```

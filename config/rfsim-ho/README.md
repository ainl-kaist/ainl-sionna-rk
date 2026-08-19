# rfsim F1 handover scenario (1 CU + 2 DUs + 1 UE)

This scenario runs an **intra-CU F1 handover** entirely in the RF simulator: a
single UE is handed between two cells (two DUs) that share one CU. It is the
only handover topology OAI supports under rfsim (see
`ext/openairinterface5g/doc/handover-tutorial.md`, "only F1 handovers are
supported"). Inter-gNB **Xn/N2 handover is not available in rfsim** — the rfsim
UE client speaks to a single server, so two independent gNBs cannot both be
heard by one UE.

```
        ┌── oai-cu (.150) ── F1 ──┬── oai-du-pci0 (.171)  PCI0 @3619.2MHz  rfsim client ─┐
AMF ─NG─┤   RRC + PDCP            │                                                       ├─▶ oai-nr-ue (.181)
        │   telnet :9090          └── oai-du-pci1 (.172)  PCI1 @3649.4MHz  rfsim client ─┘   rfsim SERVER
        │   trigger_f1_ho                                                                     2 channel models
```

## Why the rfsim roles are inverted

Normally the gNB is the rfsim server and the UE is the client. Here it is the
opposite: **the UE is the rfsim server and both DUs are clients.** rfsim allows
only one server with many clients, and the UE must be able to receive IQ from
*both* DUs at once, so it has to be the shared server. This is why the UE runs
with `--rfsimulator.serveraddr server` and each DU with
`--rfsimulator.serveraddr 192.168.71.181` (the UE).

## Why handover is triggered manually

The OAI soft-UE does not complete measurement reporting, so it cannot ask the
network to hand it over. Instead the CU exposes a telnet `ci` command,
`trigger_f1_ho`, that forces the handover. (A real COTS 5G modem *can* report
measurements and trigger an A3-event handover on its own — see
`neighbour-config.conf` and the COTS section of the OAI tutorial.)

## Run it

```bash
cd config/rfsim-ho
./start_handover.sh up        # core -> CU -> DU0 -> UE -> DU1, in that order
./start_handover.sh status    # which DU serves the UE right now
./start_handover.sh ho        # trigger one handover (round-robins DU0 <-> DU1)
./start_handover.sh watch     # live view of the serving DU
./start_handover.sh down
```

The manual trigger, if you prefer to issue it yourself:

```bash
echo ci trigger_f1_ho | ncat 192.168.71.150 9090
```

You can also loop it (e.g. every 15 s) to ping-pong the UE between cells:

```bash
while true; do echo ci trigger_f1_ho | ncat -N 192.168.71.150 9090; sleep 15; done
```

## What differs from the main single-gNB stack

- gNB side is **3 containers** (CU + 2 DUs) instead of the one monolithic
  `oai-gnb`. Same images (`oai-gnb-cuda` / `oai-nr-ue-cuda`) — only conf and
  CLI flags differ; **no rebuild needed**.
- Core (mysql/amf/smf/upf/ext-dn) is unchanged and reuses
  `../common/sys_config.yaml`. F1 handover is intra-CU, so there is a single
  NG connection (CU ↔ AMF).
- PLMN is 262/99 (sd 0xffffff), matching this project's core and UE IMSI.

## Adding more DUs (3, 4, …)

The architecture scales — the rfsim server accepts up to 250 clients
(`MAX_FD_RFSIMU`), and the CU's `remote_s_address = 0.0.0.0` accepts any number
of DUs; `trigger_f1_ho` round-robins across all of them. Per extra DU:

1. Copy the `oai-du-pci1` service block in `docker-compose.yaml`; give it a new
   container name and IP (e.g. `.173`).
2. In its `USE_ADDITIONAL_OPTIONS`, bump the overrides: `gNB_DU_ID` (3586, …),
   `nr_cellid`, `physCellId` (2, …), `absoluteFrequencySSB` / point A, and
   `MACRLCs.[0].local_n_address` (its own IP).
3. Add one more channel model to `nrue.uicc.conf`
   (`model_name = "rfsimu_channel_ue2"`).
4. Give it a non-overlapping thread pool in `.env`, and add it to
   `start_handover.sh` after the UE is up.

The real ceiling is host CPU/GPU: each DU runs a full PHY.

## Troubleshooting: UE stuck at "starting", never gets a tunnel IP

Symptom: `start_handover.sh up` times out at the UE step; `oai-nr-ue` stays
`health: starting` and has no `oaitun_ue1` IP, while `oai-du-pci0` shows a few
restarts. First check that the UE command line includes `--ssb 516`; without it the UE can
connect to the rfsim socket but fail PHY sync. If the option is present and the
stack is still wedged after manual `docker` juggling, recreate the handover
stack so the scripted order is restored:

```bash
cd config/rfsim-ho
./start_handover.sh down
./start_handover.sh up
```

The expected order is core -> CU -> DU0 -> UE -> DU1. DU0 may retry rfsim until
the UE server starts; the UE should then attach to DU0 and create `oaitun_ue1`.

## CU binary patch (why `bin/nr-softmodem-cu` exists)

The stock `oai-gnb-cuda` image **crashes when run as a pure CU**. The fork's
channel-emulation hook in `ext/openairinterface5g/executables/nr-softmodem.c`
unconditionally does `NR_DL_FRAME_PARMS *fp = &RC.gNB[0]->frame_parms;` before
`init_plugins(fp)`. A CU has no L1/PHY, so `RC.gNB[0]` is NULL → SIGSEGV.

`bin/nr-softmodem-cu` is a rebuilt binary with that one line guarded:

```c
NR_DL_FRAME_PARMS *fp = (RC.gNB && RC.gNB[0]) ? &RC.gNB[0]->frame_parms : NULL; // CU has no L1
```

It is bind-mounted over the CU's binary in `docker-compose.yaml` (the two DUs
run the stock image unchanged, since they do have a PHY). To reproduce it:

```bash
docker run -d --name cu-build --entrypoint sleep ran-build-cuda:latest infinity
docker exec cu-build sed -i \
  's|    NR_DL_FRAME_PARMS \*fp = &RC.gNB\[0\]->frame_parms;|    NR_DL_FRAME_PARMS *fp = (RC.gNB \&\& RC.gNB[0]) ? \&RC.gNB[0]->frame_parms : NULL;|' \
  /oai-ran/executables/nr-softmodem.c
docker exec cu-build bash -c 'cd /oai-ran/cmake_targets/ran_build/build && ninja nr-softmodem'
docker cp cu-build:/oai-ran/cmake_targets/ran_build/build/nr-softmodem ./bin/nr-softmodem-cu
docker rm -f cu-build
```

**Permanent fix:** apply that guard in the fork's `nr-softmodem.c` and rebuild
the images (`make build-gnb`), then drop the bind-mount. Worth upstreaming to the
fork — it makes the plugin build usable in any CU/DU-split deployment.

## Wiring in the Sionna RT channel (later)

In the CU/DU split the PHY lives in the **DUs**, so the Sionna CIR hooks
(`--cir-folder` / `--cir-zmq-num-taps`, as in the main `.env`) attach to each
`oai-du-pciN` service, not the CU. The `../../plugins` mount is already present
on the DUs for that purpose. Start with the plain `chanmod` AWGN channel here to
confirm handover works, then add the CIR source per DU.

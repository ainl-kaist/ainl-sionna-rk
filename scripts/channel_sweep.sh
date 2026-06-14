#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Channel parameter sweep for the OAI rfsimulator (chanmod) in rfsim mode.
#
# For each value in the sweep, this script:
#   1. Sends `channelmod modify <model> <param> <value>` to the rfsimulator
#      telnet server (DL via the UE container, UL via the gNB container).
#   2. Runs a short iperf3 test and records the throughput.
#   3. Prints a results table at the end.
#
# The telnet control uses a SINGLE persistent connection for the whole sweep
# (fed via a coprocess). It NEVER sends `exit` -- in the OAI telnet server
# `exit` terminates the softmodem, not just the session.
#
# Prerequisites:
#   - System already running in rfsim mode with chanmod enabled
#     (./scripts/start_system.sh rfsim) and the UE connected (oaitun_ue1 up).
#
# Usage:
#   ./scripts/channel_sweep.sh [options]
#
# Options (all optional; defaults in []):
#   -p <param>     channelmod parameter to sweep        [ploss]
#   -v <list>      comma-separated values to sweep       [10,20,30,40]
#   -d <dir>       traffic direction: dl | ul            [dl]
#   -m <index>     channel model index                   [auto: dl=0, ul=1]
#   -t <seconds>   iperf3 duration per step              [8]
#   -s <ip>        iperf3 server (traffic generator)     [192.168.72.135]
#   -u <ip>        UE tunnel IP (auto-detected if unset) [auto]
#
# Examples:
#   ./scripts/channel_sweep.sh                                   # default DL path-loss sweep (near->far)
#   ./scripts/channel_sweep.sh -d ul -v 10,20,30,40            # uplink path-loss sweep
#   ./scripts/channel_sweep.sh -p noise_power_dB -v -20,-10,0   # noise-floor sweep (less physical)
#
# Note on realism: path loss (ploss, dB) models distance / shadowing / blockage --
# the received signal weakens as the UE moves away, which is what really varies in
# the field. Sweeping noise_power_dB instead pins the signal and moves the thermal
# noise floor, which is not physically how a link degrades; keep it for SNR probing.
#

set -euo pipefail

# ---- defaults ----------------------------------------------------------------
PARAM="ploss"                 # path loss in dB (distance/shadowing); higher = farther
VALUES="10,20,30,40"          # additional path loss in dB (0 omitted: never physical)
DIRECTION="dl"
MODEL_IDX=""                   # empty => auto-select per direction (dl=0, ul=1)
DURATION=8
IPERF_SERVER="192.168.72.135"
UE_IP=""                      # empty => auto-detect from oaitun_ue1
TELNET_PORT=9090

# ---- parse args --------------------------------------------------------------
while getopts "p:v:d:m:t:s:u:h" opt; do
    case "$opt" in
        p) PARAM="$OPTARG" ;;
        v) VALUES="$OPTARG" ;;
        d) DIRECTION="$OPTARG" ;;
        m) MODEL_IDX="$OPTARG" ;;
        t) DURATION="$OPTARG" ;;
        s) IPERF_SERVER="$OPTARG" ;;
        u) UE_IP="$OPTARG" ;;
        h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option. Use -h for help." >&2; exit 1 ;;
    esac
done

log()  { echo -e "\033[1;32m[sweep]\033[0m $*"; }
warn() { echo -e "\033[1;33m[sweep]\033[0m $*"; }
err()  { echo -e "\033[1;31m[sweep]\033[0m $*" >&2; }

# ---- direction wiring --------------------------------------------------------
# The channel model is applied at the RECEIVER (the side whose telnet reports
# "model owner: rfsimulator"), so each direction is controlled on a different
# container AND a different model index:
#   DL (gNB->UE): rfsimu_channel_enB0 = model 0, active on the UE receive side
#                 -> modify model 0 through the UE container's telnet server.
#   UL (UE->gNB): rfsimu_channel_ue0  = model 1, active on the gNB receive side
#                 -> modify model 1 through the gNB container's telnet server.
# (On the gNB, model 0 is "not set", so modifying it would NOT affect UL.)
# iperf3 downlink uses -R (reverse); uplink uses forward.
case "$DIRECTION" in
    dl) TELNET_CTR="oai-nr-ue"; IPERF_FLAGS="-R"; DEFAULT_MODEL_IDX=0 ;;
    ul) TELNET_CTR="oai-gnb";   IPERF_FLAGS="";   DEFAULT_MODEL_IDX=1 ;;
    *)  err "Direction must be 'dl' or 'ul'."; exit 1 ;;
esac

# Use the per-direction default model unless the user forced one with -m.
MODEL_IDX="${MODEL_IDX:-$DEFAULT_MODEL_IDX}"

# ---- sanity checks -----------------------------------------------------------
for c in "$TELNET_CTR" oai-nr-ue; do
    if ! docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
        err "Container $c is not running. Start the system first (./scripts/start_system.sh rfsim)."
        exit 1
    fi
done

# Auto-detect the UE tunnel IP if not provided.
if [[ -z "$UE_IP" ]]; then
    UE_IP=$(docker exec oai-nr-ue ip -4 addr show oaitun_ue1 2>/dev/null \
            | grep -oP 'inet\s+\K[\d.]+' || true)
    if [[ -z "$UE_IP" ]]; then
        err "Could not auto-detect UE IP (oaitun_ue1 down?). Is the UE connected?"
        exit 1
    fi
fi

# ---- persistent telnet coprocess --------------------------------------------
# One long-lived connection reads channelmod commands from its stdin, one per
# line, and forwards them over a single socket. No reconnect churn, no `exit`.
coproc TELNET { docker exec -i "$TELNET_CTR" python3 -u -c '
import socket, sys, time
port = '"$TELNET_PORT"'
s = socket.create_connection(("127.0.0.1", port), timeout=5)
sys.stderr.write("telnet-connected\n"); sys.stderr.flush()
for line in sys.stdin:           # one channelmod command per line
    cmd = line.strip()
    if not cmd:
        continue
    s.sendall((cmd + "\n").encode())
    time.sleep(0.3)              # let the server apply it
# stdin closed -> sweep done; drop the socket once.
s.close()
'; }
TELNET_PID=$TELNET_PID

cleanup() {
    # Close the coprocess stdin so the telnet connection ends cleanly.
    { exec {TELNET[1]}>&-; } 2>/dev/null || true
    wait "$TELNET_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Make sure the connection actually came up.
sleep 1
if ! kill -0 "$TELNET_PID" 2>/dev/null; then
    err "Telnet coprocess failed to start (could not reach $TELNET_CTR:$TELNET_PORT)."
    exit 1
fi

send_chanmod() { echo "$1" >&"${TELNET[1]}"; }

# ---- run the sweep -----------------------------------------------------------
log "Channel parameter sweep"
log "  direction : $DIRECTION   (telnet -> $TELNET_CTR, model $MODEL_IDX)"
log "  parameter : $PARAM"
log "  values    : $VALUES"
log "  iperf3    : ${DURATION}s per step, server $IPERF_SERVER, UE $UE_IP"
echo

declare -a RES_VAL RES_TPUT
IFS=',' read -ra VLIST <<< "$VALUES"

# Warm-up burst: on a fresh connection the gNB link adaptation starts at a low
# MCS and takes several seconds to ramp up. Without this, the FIRST swept value
# reads artificially low. Run one throwaway transfer first (result discarded).
log "Warm-up transfer (ramping link adaptation, result discarded) ..."
docker exec oai-nr-ue iperf3 -B "$UE_IP" -c "$IPERF_SERVER" $IPERF_FLAGS \
    -t 5 -J >/dev/null 2>&1 || true

for val in "${VLIST[@]}"; do
    val="$(echo "$val" | xargs)"   # trim whitespace
    log "Setting $PARAM = $val ..."
    send_chanmod "channelmod modify $MODEL_IDX $PARAM $val"
    sleep 2   # let the channel + gNB link adaptation (MCS) settle before measuring

    # -O 2: omit the first 2 s so TCP slow-start / MCS ramp-up don't drag the
    # reported steady-state throughput down (matters most for the first step).
    tput=$(docker exec oai-nr-ue iperf3 -B "$UE_IP" -c "$IPERF_SERVER" $IPERF_FLAGS \
            -O 2 -t "$DURATION" -J 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('%.2f' % (d['end']['sum_received']['bits_per_second'] / 1e6))
except Exception:
    print('ERR')
") || tput="ERR"

    log "  -> ${tput} Mbps"
    RES_VAL+=("$val")
    RES_TPUT+=("$tput")
done

# ---- results table -----------------------------------------------------------
echo
echo "==================== RESULTS ===================="
# A run measures one direction only (-d), so label the column accordingly.
printf "  %-18s | %-15s\n" "$PARAM" "$(echo "$DIRECTION" | tr '[:lower:]' '[:upper:]') Mbps"
printf "  %-18s-+-%-15s\n" "------------------" "---------------"
for i in "${!RES_VAL[@]}"; do
    printf "  %-18s | %-15s\n" "${RES_VAL[$i]}" "${RES_TPUT[$i]}"
done
echo "================================================="
echo
# Restore the channel to the first (mildest) swept value so the link recovers.
# Leaving it at a link-killing value (e.g. very high path loss) makes the UE
# thrash on RRC re-establishment, which can destabilise the softmodem.
reset_val="${VLIST[0]}"
reset_val="$(echo "$reset_val" | xargs)"
log "Restoring $PARAM = $reset_val (first swept value) to keep the link healthy."
send_chanmod "channelmod modify $MODEL_IDX $PARAM $reset_val"
sleep 1

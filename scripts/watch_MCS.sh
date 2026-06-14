#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 AINL. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# watch_MCS.sh — follow a container log and show the link-quality metrics that
# actually respond to channel changes (e.g. while ./scripts/channel_sweep.sh
# drives ploss). OAI does NOT print a steady "SNR ... dB" stream on the UE; the
# useful live signals are the periodic NR_MAC stats:
#
#   gNB (default, richest): per-UE  DL MCS + BLER,  UL MCS + SNR + BLER
#   UE:                     DL/UL harq (ok/nack), avg code rate, avg bit/symbol
#
# Each line is prefixed with the channel value currently set by channel_sweep.sh,
# read from its state file ($SWEEP_STATE_FILE, default /tmp/oai_chan_sweep.state)
# so you can line up "ploss=N" against the link's response. The state file is
# used instead of polling telnet, because the OAI telnet server is single-client
# and the running sweep holds that connection.
#
# Note: MCS only climbs when traffic is flowing, so run this alongside a sweep
# or an iperf3 transfer to see the channel take effect.
#
# Usage:
#   ./scripts/watch_MCS.sh             # follow oai-gnb (DL/UL MCS, UL SNR, BLER)
#   ./scripts/watch_MCS.sh oai-nr-ue   # follow the UE (harq, code rate, bit/sym)
#
set -uo pipefail
CTR="${1:-oai-gnb}"
STATE_FILE="${SWEEP_STATE_FILE:-/tmp/oai_chan_sweep.state}"

if ! docker inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -q true; then
    echo "[watch_MCS] container $CTR is not running." >&2
    exit 1
fi

# Current swept value (e.g. "ploss=5") from channel_sweep.sh, or "--" if idle.
cur_state() {
    if [[ -f "$STATE_FILE" ]]; then
        awk '{for(i=1;i<=NF;i++){split($i,a,"=");kv[a[1]]=a[2]}}
             END{printf "%s=%s", (kv["param"]?kv["param"]:"?"),
                                 (kv["value"]!=""?kv["value"]:"?")}' "$STATE_FILE" 2>/dev/null
    else
        printf -- "--"
    fi
}

strip_ansi='s/\x1b\[[0-9;]*m//g'
echo "[watch_MCS] following $CTR  (prefix = current channel from $STATE_FILE).  Ctrl-C to stop."

if [[ "$CTR" == *gnb* || "$CTR" == *enb* ]]; then
    echo "[watch_MCS] per-UE   DL: MCS/BLER   UL: MCS/SNR/BLER"
    docker logs -f --tail 40 "$CTR" 2>&1 \
        | sed -u "$strip_ansi" \
        | grep --line-buffered -E 'dlsch_rounds|ulsch_rounds' \
        | while IFS= read -r line; do
            if [[ "$line" == *dlsch_rounds* ]]; then
                m=$(sed -E 's/.*UE ([0-9a-fA-F]+): dlsch.* BLER ([0-9.]+) MCS \([0-9]+\) ([0-9]+).*/DL  ue \1   MCS \3   BLER \2/' <<<"$line")
            else
                m=$(sed -E 's/.*UE ([0-9a-fA-F]+): ulsch.* BLER ([0-9.]+) MCS \([0-9]+\) ([0-9]+).*SNR ([0-9.-]+) dB.*/UL  ue \1   MCS \3   SNR \4 dB   BLER \2/' <<<"$line")
            fi
            printf '[%-10s] %s\n' "$(cur_state)" "$m"
          done
else
    echo "[watch_MCS] UE   bad DCI | DL harq ok/nack | UL code rate + bit/symbol"
    docker logs -f --tail 40 "$CTR" 2>&1 \
        | sed -u "$strip_ansi" \
        | grep --line-buffered -E 'cumulated bad DCI|DL harq:|Ul harq:' \
        | while IFS= read -r line; do
            m=$(sed -E \
                -e 's/.*cumulated bad DCI ([0-9]+).*/badDCI \1/' \
                -e 's/.*DL harq: ([0-9]+)\/([0-9]+).*/DL harq  ok \1  nack \2/' \
                -e 's/.*Ul harq:.*avg code rate ([0-9.]+), avg bit\/symbol ([0-9.]+).*/UL codeRate \1  bit\/sym \2/' \
                <<<"$line")
            printf '[%-10s] %s\n' "$(cur_state)" "$m"
          done
fi

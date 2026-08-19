#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 AINL. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# watch_MCS.sh — follow an OAI log and show the link-quality metrics that
# actually respond to channel changes (e.g. while ./scripts/channel_sweep.sh
# drives ploss). OAI prints no steady "SNR ... dB" stream, so we read NR_MAC
# stats:
#
#   dl/ul/both (gNB log):  per-UE  DL MCS+BLER  /  UL MCS+SNR+BLER
#   ue        (UE log):    DL/UL harq (ok/nack), avg code rate, avg bit/symbol
#
# Each line is prefixed with the OAI log timestamp (leading seconds field of the
# followed log line -- monotonic, increasing over time) and then the channel
# value currently set by channel_sweep.sh,
# read from its state file ($SWEEP_STATE_FILE, default /tmp/oai_chan_sweep.state)
# so you can line up "ploss=N" against the link's response. The state file is
# used instead of polling telnet, because the OAI telnet server is single-client
# and the running sweep holds that connection.
#
# Note: MCS only climbs when traffic is flowing, so run this alongside a sweep
# or an iperf3 transfer to see the channel take effect.
#
# Usage:
#   ./scripts/watch_MCS.sh          # both directions (gNB)
#   ./scripts/watch_MCS.sh dl       # downlink only  (DL MCS / BLER)
#   ./scripts/watch_MCS.sh ul       # uplink only    (UL MCS / SNR / BLER)
#   ./scripts/watch_MCS.sh ue       # UE side        (harq, code rate, bit/symbol)
#
# Container override:  WATCH_CTR=oai-gnb ./scripts/watch_MCS.sh dl
#
set -uo pipefail

DIR="${1:-both}"
STATE_FILE="${SWEEP_STATE_FILE:-/tmp/oai_chan_sweep.state}"

case "$DIR" in
    dl|DL)     DIR=dl;   DEF_CTR=oai-gnb;   pat='dlsch_rounds' ;;
    ul|UL)     DIR=ul;   DEF_CTR=oai-gnb;   pat='ulsch_rounds' ;;
    both|all)  DIR=both; DEF_CTR=oai-gnb;   pat='dlsch_rounds|ulsch_rounds' ;;
    ue|UE)     DIR=ue;   DEF_CTR=oai-nr-ue; pat='cumulated bad DCI|DL harq:|Ul harq:' ;;
    *) echo "usage: $0 [dl|ul|both|ue]" >&2; exit 1 ;;
esac
CTR="${WATCH_CTR:-$DEF_CTR}"

if ! docker inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -q true; then
    echo "[watch_MCS] container $CTR is not running." >&2
    exit 1
fi

TELNET_PORT="${TELNET_PORT:-9090}"
LIVE_FILE="/tmp/oai_chan_live.$$"   # background poller writes the live ploss here when idle

# Read the current path-loss of <model> from the rfsimulator telnet server in
# <container> (read-only `channelmod show current`). Prints e.g. "10" or "-5".
read_ploss() {  # <container> <model-index>
    docker exec -i "$1" python3 -u -c '
import socket, sys, time
s = socket.create_connection(("127.0.0.1", '"$TELNET_PORT"'), timeout=3)
s.sendall(b"channelmod show current\n")
time.sleep(0.3)
s.settimeout(1)
data = b""
try:
    while True:
        d = s.recv(4096)
        if not d: break
        data += d
except Exception:
    pass
s.close()
sys.stdout.write(data.decode("latin1"))
' 2>/dev/null | awk -v m="$2" '
    /^model [0-9]+ / { cur=$2 }
    cur==m && /path loss:/ {
        for(i=1;i<=NF;i++) if($i=="loss:") { printf "%g", $(i+1); exit }
    }'
}

# Read the live channel value(s) for this direction once into LIVE_FILE.
write_live() {
    local dl="" ul=""
    case "$DIR" in dl|ue|both) dl=$(read_ploss oai-nr-ue 0) ;; esac
    case "$DIR" in ul|both)    ul=$(read_ploss oai-gnb 1)   ;; esac
    printf 'dl=%s ul=%s\n' "$dl" "$ul" > "$LIVE_FILE" 2>/dev/null
}

# Background poller: while NO sweep owns the telnet (STATE_FILE absent), refresh
# the live value(s) every 2s. When a sweep IS running it backs off, so it never
# competes for the single-client telnet.
poll_live() {
    while true; do
        [[ -f "$STATE_FILE" ]] || write_live
        sleep 2
    done
}

# Channel value for the prefix. Priority:
#   1) a running channel_sweep.sh (STATE_FILE)        -> "<param>=<value>"
#   2) the live telnet poll (LIVE_FILE) for this line -> "ploss=<v>"
#   3) "--" if neither is available yet.
cur_state() {  # optional arg: dl|ul -> which live value to show (matters for "both")
    if [[ -f "$STATE_FILE" ]]; then
        awk '{for(i=1;i<=NF;i++){split($i,a,"=");kv[a[1]]=a[2]}}
             END{printf "%s=%s", (kv["param"]?kv["param"]:"?"),
                                 (kv["value"]!=""?kv["value"]:"?")}' "$STATE_FILE" 2>/dev/null
        return
    fi
    if [[ -f "$LIVE_FILE" ]]; then
        awk -v tag="${1:-dl}" '{for(i=1;i<=NF;i++){split($i,a,"=");kv[a[1]]=a[2]}}
             END{v=kv[tag]; if(v!="") printf "ploss=%s", v; else printf "--"}' "$LIVE_FILE" 2>/dev/null
        return
    fi
    printf -- "--"
}

strip_ansi='s/\x1b\[[0-9;]*m//g'

# Prime LIVE_FILE once synchronously so even the --tail backlog gets labelled,
# then start the background poller. Both are cleaned up on exit.
[[ -f "$STATE_FILE" ]] || write_live
poll_live &
POLLER_PID=$!
cleanup() { kill "$POLLER_PID" 2>/dev/null; rm -f "$LIVE_FILE"; }
trap cleanup EXIT INT TERM

echo "[watch_MCS] following $CTR  dir=$DIR  (prefix = log timestamp + channel: sweep state $STATE_FILE, else live telnet).  Ctrl-C to stop."

# NOTE: we do NOT pre-filter with grep, because the per-UE stat lines that carry
# the metrics have NO timestamp of their own -- it sits on the block header line
# that precedes them (gNB: "... Frame.Slot N.N"; UE: "... cumulated bad DCI N").
# So we follow every line, remember the most recent timestamp, and attach it to
# the metric lines we emit.
ts="--"
docker logs -f --tail 40 "$CTR" 2>&1 \
    | sed -u "$strip_ansi" \
    | while IFS= read -r line; do
        # A line beginning with "<sec>.<usec>" carries the current log timestamp.
        if [[ "$line" =~ ^([0-9]+\.[0-9]+) ]]; then
            ts="${BASH_REMATCH[1]}"
        fi
        # Only emit for the metric lines we care about.
        [[ "$line" =~ $pat ]] || continue
        if [[ "$DIR" == ue ]]; then
            tag=dl   # UE-side stats are the DL receive (model 0)
            m=$(sed -E \
                -e 's/.*cumulated bad DCI ([0-9]+).*/badDCI \1/' \
                -e 's/.*DL harq: ([0-9]+)\/([0-9]+).*/DL harq  ok \1  nack \2/' \
                -e 's/.*Ul harq:.*avg code rate ([0-9.]+), avg bit\/symbol ([0-9.]+).*/UL codeRate \1  bit\/sym \2/' \
                <<<"$line")
        elif [[ "$line" == *dlsch_rounds* ]]; then
            tag=dl
            m=$(sed -E 's/.*UE ([0-9a-fA-F]+): dlsch.* BLER ([0-9.]+) MCS \([0-9]+\) ([0-9]+).*/DL  ue \1   MCS \3   BLER \2/' <<<"$line")
        else
            tag=ul
            m=$(sed -E 's/.*UE ([0-9a-fA-F]+): ulsch.* BLER ([0-9.]+) MCS \([0-9]+\) ([0-9]+).*SNR ([0-9.-]+) dB.*/UL  ue \1   MCS \3   SNR \4 dB   BLER \2/' <<<"$line")
        fi
        printf '[%-14s] [%-10s] %s\n' "$ts" "$(cur_state "$tag")" "$m"
      done

#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Start EXTRA soft-UEs alongside the primary oai-nr-ue, so several UEs are
# attached to the same gNB at once (rfsim mode). The OAI rfsimulator server in
# the gNB accepts up to 250 client connections, broadcasting DL to each and
# summing their UL -- so multiple full-stack UEs work against one gNB.
#
# Each extra UE gets its own:
#   - container name   (oai-nr-ue2, oai-nr-ue3, ...)
#   - public_net IP    (192.168.71.151, .152, ...)
#   - provisioned IMSI (from the spares already in config/common/oai_db.sql)
#   - CPU thread-pool  (offset so UEs don't fight over the primary's cores)
# All connect to the same gNB rfsim server (192.168.71.140:4043).
#
# The primary UE (oai-nr-ue, IMSI ...000832, started by start_ue.sh /
# start_system.sh) is left untouched -- this only adds UEs #2, #3, ...
#
# Usage:
#   ./scripts/start_ues.sh [-n <count>] [config]
#     -n <count>   number of EXTRA UEs to start   [default 2]
#     config       per-config .env to source       [default rfsim]
#
# Limit: only as many extra UEs as there are SPARE provisioned IMSIs (2 here:
# ...001101 and ...016069). To go higher, add more subscribers to
# config/common/oai_db.sql (same key/opc, new IMSI) and extend SPARE_IMSIS.
#
# Stop them again with: ./scripts/stop_ues.sh

set -euo pipefail

# suppress outputs from pushd/popd (kept for symmetry with start_ue.sh)
function pushd() { command pushd "$@" > /dev/null; }
function popd()  { command popd  "$@" > /dev/null; }

# ---- spare subscribers (the primary oai-nr-ue already uses ...000832) --------
SPARE_IMSIS=(262990100001101 262990100016069)

# ---- defaults ----------------------------------------------------------------
COUNT=2
PUBLIC_NET="oai-public-net"      # external network created by docker-compose
RFSIM_SERVER="192.168.71.140"    # gNB rfsim server address
IP_BASE="192.168.71"             # extra UE #i -> ${IP_BASE}.$((150+i))

# ---- parse args --------------------------------------------------------------
while getopts "n:h" opt; do
    case "$opt" in
        n) COUNT="$OPTARG" ;;
        h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option. Use -h for help." >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
CONFIG_NAME=${1:-rfsim}

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 1 )); then
    echo "Error: -n must be a positive integer." >&2; exit 1
fi
if (( COUNT > ${#SPARE_IMSIS[@]} )); then
    echo "Error: only ${#SPARE_IMSIS[@]} spare IMSI(s) provisioned; cannot start $COUNT extra UEs." >&2
    echo "       Add subscribers to config/common/oai_db.sql and extend SPARE_IMSIS." >&2
    exit 1
fi

# ---- locate repo + env -------------------------------------------------------
project_root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
configs_dir="${project_root}/config"
env_file="${configs_dir}/${CONFIG_NAME}/.env"
template="${project_root}/config/common/nrue.uicc.conf"
gen_dir="${project_root}/config/common/generated"

[[ -f "$env_file" ]] || { echo "Error: .env not found at $env_file" >&2; exit 1; }
[[ -f "$template" ]] || { echo "Error: UE config template not found at $template" >&2; exit 1; }

# pull UE_IMAGE / UE_TAG / UE_RF_OPTIONS / UE_EXTRA_OPTIONS from the .env
set -a
# shellcheck disable=SC1090
source "$env_file"
set +a
UE_IMAGE=${UE_IMAGE:-oai-nr-ue-cuda}
UE_TAG=${UE_TAG:-latest}
UE_RF_OPTIONS=${UE_RF_OPTIONS:-"--rfsim --telnetsrv --rfsimulator.options chanmod --rfsimulator.serveraddr ${RFSIM_SERVER}"}
UE_EXTRA_OPTIONS=${UE_EXTRA_OPTIONS:-"-C 3319680000 -r 106 --numerology 1 --ssb 516 --thread-pool 3,4"}

# ---- preflight ---------------------------------------------------------------
if ! docker network inspect "$PUBLIC_NET" >/dev/null 2>&1; then
    echo "Error: docker network '$PUBLIC_NET' not found. Start the system first" >&2
    echo "       (./scripts/start_system.sh ${CONFIG_NAME})." >&2
    exit 1
fi
if ! docker inspect -f '{{.State.Running}}' oai-gnb 2>/dev/null | grep -q true; then
    echo "Warning: oai-gnb is not running; the extra UEs will keep retrying to"
    echo "         connect to the rfsim server until it is up."
fi

mkdir -p "$gen_dir"

# ---- launch each extra UE ----------------------------------------------------
for (( i=1; i<=COUNT; i++ )); do
    imsi="${SPARE_IMSIS[$((i-1))]}"
    name="oai-nr-ue$((i+1))"                 # #2, #3, ...
    ip="${IP_BASE}.$((150+i))"               # .151, .152, ...
    cores="$((3+2*i)),$((4+2*i))"            # 5,6 / 7,8 (avoid primary 3,4 & gNB 15-19)
    cfg="${gen_dir}/nrue.uicc.${imsi}.conf"

    # render a per-UE config: same key/opc/dnn, only the IMSI differs
    sed "s/imsi = \"262990100000832\"/imsi = \"${imsi}\"/" "$template" > "$cfg"

    echo "Starting $name  (IMSI ${imsi}, IP ${ip}, cores ${cores})"
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" \
        --runtime nvidia \
        --cap-add NET_ADMIN --cap-add NET_RAW --cap-add SYS_NICE \
        --cap-add IPC_LOCK --cap-add SYS_PTRACE \
        --restart unless-stopped \
        --device /dev/net/tun \
        --network "$PUBLIC_NET" --ip "$ip" \
        -e USE_ADDITIONAL_OPTIONS="${UE_RF_OPTIONS} --log_config.global_log_options level,nocolor,time $(echo "$UE_EXTRA_OPTIONS" | sed -E "s/--thread-pool [0-9,]+/--thread-pool ${cores}/")" \
        -v "$cfg":/opt/oai-nr-ue/etc/nr-ue.conf \
        "${UE_IMAGE}:${UE_TAG}" >/dev/null
done

# ---- wait for tunnels (UE actually attached) ---------------------------------
echo
for (( i=1; i<=COUNT; i++ )); do
    name="oai-nr-ue$((i+1))"
    echo -n "Waiting for $name tunnel (oaitun_ue1) ... "
    ue_ip=""
    start_time=$(date +%s)
    while true; do
        ue_ip=$(docker exec "$name" ip -4 addr show oaitun_ue1 2>/dev/null \
                | grep -oP 'inet\s+\K[\d.]+' || true)
        [[ -n "$ue_ip" ]] && { echo "up ($ue_ip)"; break; }
        if (( $(date +%s) - start_time >= 60 )); then
            echo "still down after 60s (check 'docker logs $name')"; break
        fi
        sleep 2
    done
done

echo
echo "Done. Connected UEs:"
for c in oai-nr-ue $(for ((i=1;i<=COUNT;i++)); do echo "oai-nr-ue$((i+1))"; done); do
    ip=$(docker exec "$c" ip -4 addr show oaitun_ue1 2>/dev/null | grep -oP 'inet\s+\K[\d.]+' || echo "-")
    printf "  %-12s tunnel=%s\n" "$c" "$ip"
done

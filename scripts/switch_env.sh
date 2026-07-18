#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Switch between the two mutually-exclusive OAI environments:
#   * single : the original monolithic single-gNB stack   (config/common)
#   * ho     : the CU + 2xDU F1-handover stack             (config/rfsim-ho)
#
# They share the same docker network (oai-public-net) and container names
# (oai-mysql, oai-amf, oai-nr-ue, ...), so only one can run at a time. This
# script brings the OTHER one fully down, then brings the requested one up.
# The monitoring stack (grafana/prometheus/...) is on its own network and is
# left untouched.
#
# Usage:
#   ./scripts/switch_env.sh ho                 # -> handover stack
#   ./scripts/switch_env.sh single [rfsim|b200]  # -> single gNB (default rfsim)
#   ./scripts/switch_env.sh status             # show which environment is up
#   ./scripts/switch_env.sh down               # bring BOTH down (idle)
#
set -euo pipefail

repo_root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
ho_dir="${repo_root}/config/rfsim-ho"

have() { docker ps -a --format '{{.Names}}' | grep -qxE "$1"; }

current_env() {
    if have 'oai-cu' || have 'oai-du-pci[0-9]+'; then echo "ho"
    elif have 'oai-gnb'; then echo "single"
    else echo "none"; fi
}

down_single() {
    echo ">> bringing down single-gNB stack (+ extra UEs)"
    "${repo_root}/scripts/stop_ues.sh"    >/dev/null 2>&1 || true
    "${repo_root}/scripts/stop_system.sh" || true
}

down_ho() {
    echo ">> bringing down handover stack"
    ( cd "$ho_dir" && ./start_handover.sh down ) || true
}

case "${1:-status}" in
    ho)
        echo "== switching to: handover (CU + 2xDU) =="
        down_single
        ( cd "$ho_dir" && ./start_handover.sh up )
        ;;
    single)
        profile="${2:-rfsim}"
        if [[ "$profile" != "rfsim" && "$profile" != "b200" ]]; then
            echo "Error: profile must be 'rfsim' or 'b200' (got '$profile')"; exit 1
        fi
        echo "== switching to: single gNB (profile: $profile) =="
        down_ho
        "${repo_root}/scripts/start_system.sh" "$profile"
        echo ">> single gNB up. Start extra soft-UEs with ./scripts/start_ues.sh if needed."
        ;;
    down)
        echo "== bringing BOTH environments down =="
        down_ho
        down_single
        echo ">> idle (monitoring stack, if any, left running)."
        ;;
    status)
        case "$(current_env)" in
            ho)     echo "current environment: HANDOVER (oai-cu + oai-du-pci0/1)";;
            single) echo "current environment: SINGLE gNB (oai-gnb)";;
            none)   echo "current environment: NONE (neither stack is up)";;
        esac
        ;;
    *)
        echo "usage: $0 {ho | single [rfsim|b200] | status | down}"; exit 1 ;;
esac

#!/usr/bin/env bash
#
# F1 handover (rfsim) scenario driver.
#
# Start order is load-bearing (see OAI handover-tutorial.md, remark #1):
#   core -> CU -> DU0 -> UE (must fully attach to DU0) -> DU1
# because there is no channel emulation forcing cell selection: the UE has to
# lock onto DU0's SIB1 before DU1 appears.
#
# Usage:
#   ./start_handover.sh up       # bring the whole stack up in the correct order (default)
#   ./start_handover.sh ho       # trigger one F1 handover (round-robins DU0<->DU1)
#   ./start_handover.sh status   # print which DU the UE is currently served by
#   ./start_handover.sh watch    # poll status every 2s
#   ./start_handover.sh down     # tear everything down
#
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

COMPOSE="docker compose"
CU_TELNET_IP=192.168.71.150
CU_TELNET_PORT=9090
DU0_ID=3584   # gNB_DU_ID 0xe00
DU1_ID=3585   # gNB_DU_ID 0xe01

# pick a netcat that speaks to the CU telnet 'ci' module
nc_send() {  # nc_send "<line>"
    local line="$1" host="$CU_TELNET_IP" port="$CU_TELNET_PORT"
    if command -v ncat >/dev/null 2>&1; then
        echo "$line" | ncat --no-shutdown -w1 "$host" "$port"
    else
        echo "$line" | nc -q1 "$host" "$port"
    fi
}

wait_healthy() {  # wait_healthy <container> <timeout_s>
    local name="$1" timeout="${2:-120}" waited=0 st
    echo -n "  waiting for $name to be healthy "
    while :; do
        st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}nohc{{end}}' "$name" 2>/dev/null || echo "missing")
        case "$st" in
            healthy) echo " ok"; return 0 ;;
            missing) echo " (container missing)"; return 1 ;;
        esac
        if (( waited >= timeout )); then echo " TIMEOUT ($st)"; return 1; fi
        sleep 3; waited=$((waited+3)); echo -n "."
    done
}

cmd_up() {
    echo "[1/5] core network (mysql/amf/smf/upf/ext-dn)"
    $COMPOSE up -d oai-ext-dn          # pulls in mysql/amf/smf/upf via depends_on
    wait_healthy oai-ext-dn 180

    echo "[2/5] CU (RRC/PDCP, F1 handover controller)"
    $COMPOSE up -d oai-cu
    wait_healthy oai-cu 120

    echo "[3/5] DU0 (PCI 0). Expect rfsim 'connect() failed' until the UE server is up — that is normal."
    $COMPOSE up -d oai-du-pci0
    wait_healthy oai-du-pci0 120

    echo "[4/5] UE (rfsim server). Waiting until it attaches to DU0 and gets a PDU session IP..."
    $COMPOSE up -d oai-nr-ue
    wait_healthy oai-nr-ue 180

    echo "[5/5] DU1 (PCI 1) — the handover target."
    $COMPOSE up -d oai-du-pci1
    wait_healthy oai-du-pci1 120

    echo
    echo "Stack up. UE is currently on: $(current_du_label)"
    echo "Trigger a handover with:   $0 ho"
    echo "Watch which DU serves it:  $0 watch"
}

current_du_label() {
    local out
    out=$(nc_send "ci fetch_du_by_ue_id 1" 2>/dev/null || true)
    if   grep -q "$DU1_ID" <<<"$out"; then echo "DU1 (PCI 1, $DU1_ID)"
    elif grep -q "$DU0_ID" <<<"$out"; then echo "DU0 (PCI 0, $DU0_ID)"
    else echo "unknown (raw: $(tr -d '\r\n' <<<"$out"))"
    fi
}

cmd_ho() {
    echo "Before: UE on $(current_du_label)"
    echo "Triggering F1 handover..."
    nc_send "ci trigger_f1_ho" || true
    sleep 3
    echo "After:  UE on $(current_du_label)"
}

cmd_status() { echo "UE on $(current_du_label)"; }

cmd_watch() { while :; do echo "$(date +%H:%M:%S)  UE on $(current_du_label)"; sleep 2; done; }

cmd_down() { $COMPOSE down; }

case "${1:-up}" in
    up)     cmd_up ;;
    ho)     cmd_ho ;;
    status) cmd_status ;;
    watch)  cmd_watch ;;
    down)   cmd_down ;;
    *) echo "usage: $0 {up|ho|status|watch|down}"; exit 1 ;;
esac

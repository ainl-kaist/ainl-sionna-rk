#!/usr/bin/env bash
# Install a standalone ue-wwan-status command, independent of repository permissions.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: sudo ./scripts/install-ue-wwan-status.sh [--prefix DIR]

Install ue_wwan_status.py as DIR/bin/ue-wwan-status (default: /usr/local/bin/ue-wwan-status).
Run this installer again after updating ue_wwan_status.py to update the command.
A custom writable prefix can be used without sudo.

Run this installer on the UE Linux host, with ue_wwan_status.py beside it.
Users need Python 3, iproute2, and ping with permission to send ICMP probes.
This installer does not change network configuration or ping permissions.
HELP
}

prefix=/usr/local
while (($#)); do
    case "$1" in
        --prefix)
            if (($# < 2)) || [[ -z "$2" ]]; then
                echo 'Error: --prefix requires a directory.' >&2
                exit 2
            fi
            prefix=$2
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_file="$script_dir/ue_wwan_status.py"
if [[ ! -r "$source_file" ]]; then
    echo "Error: cannot read $source_file" >&2
    exit 1
fi

bin_dir="${prefix%/}/bin"
if [[ "$bin_dir" == /usr/local/bin && $EUID -ne 0 ]]; then
    echo 'Error: run this installer with sudo to install for all users.' >&2
    exit 1
fi

install -d -m 0755 -- "$bin_dir"
# Replace the directory entry atomically, including any old symlink, without
# writing through it into a developer checkout.
temp_file=$(mktemp "$bin_dir/.ue-wwan-status.XXXXXXXX")
trap 'rm -f -- "$temp_file"' EXIT
install -m 0755 -- "$source_file" "$temp_file"
if ((EUID == 0)); then
    chown root:root -- "$temp_file"
fi
mv -fT -- "$temp_file" "$bin_dir/ue-wwan-status"

printf 'Installed: %s/ue-wwan-status\n' "$bin_dir"
printf 'Ensure %s is in PATH, then run: ue-wwan-status\n' "$bin_dir"
echo 'Runtime requirements: Python 3, iproute2, and ping with ICMP permissions.'

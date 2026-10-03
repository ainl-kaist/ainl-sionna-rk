#!/usr/bin/env bash
# Install a standalone ue-wwan-status command on the UE host, from this checkout.
set -euo pipefail

default_host=ainl_jon@100.77.54.30
dest=/usr/local/bin/ue-wwan-status

usage() {
    cat <<HELP
Usage: ./scripts/install-ue-wwan-status.sh [--host USER@HOST]
       ./scripts/install-ue-wwan-status.sh --prefix DIR

Run this on the gNB host, from the repository checkout. The default copies a
stamped ue_wwan_status.py to the UE host over ssh/scp and installs it there as
$dest (root-owned, mode 0755).
The host defaults to \$UE_WWAN_HOST, or $default_host if that is unset.
The remote install needs sudo on the UE host. If it would prompt for a
password, the installer prints the command to run there and stops.

--prefix DIR installs to DIR/bin/ue-wwan-status on this machine instead.

The installed copy reports this checkout's commit with --version.
Run this installer again after updating ue_wwan_status.py to update the command.
The UE host needs Python 3, iproute2, and ping with permission to send ICMP probes.
This installer does not change network configuration or ping permissions.
HELP
}

host=${UE_WWAN_HOST:-$default_host}
prefix=
while (($#)); do
    case "$1" in
        --host|--prefix)
            if (($# < 2)) || [[ -z "$2" ]]; then
                echo "Error: $1 requires a value." >&2
                exit 2
            fi
            if [[ "$1" == --host ]]; then host=$2; else prefix=$2; fi
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done
if [[ ! "$host" =~ ^[A-Za-z0-9_][A-Za-z0-9._@-]*$ ]]; then
    echo "Error: invalid host: $host" >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_file="$script_dir/ue_wwan_status.py"
if [[ ! -r "$source_file" ]]; then
    echo "Error: cannot read $source_file" >&2
    exit 1
fi

# Read-only describe: optional locks off so sudo never rewrites .git/index as root.
version=$(GIT_OPTIONAL_LOCKS=0 git -C "$script_dir" describe --always --dirty 2>/dev/null) || version=unknown
if [[ ! "$version" =~ ^[A-Za-z0-9._-]+$ ]]; then
    version=unknown
fi

stamp() {
    sed "s/^__version__ = .*/__version__ = '$version'/" -- "$source_file" >"$1"
    if ! grep -qxF -- "__version__ = '$version'" "$1"; then
        echo "Error: no __version__ line to stamp in $source_file" >&2
        exit 1
    fi
    chmod 0755 -- "$1"
}

if [[ -n "$prefix" ]]; then
    bin_dir="${prefix%/}/bin"
    if [[ "$bin_dir" == /usr/local/bin && $EUID -ne 0 ]]; then
        echo 'Error: run with sudo to install into /usr/local/bin on this machine.' >&2
        exit 1
    fi
    install -d -m 0755 -- "$bin_dir"
    # Replace the directory entry atomically, including any old symlink, without
    # writing through it into a developer checkout.
    temp_file=$(mktemp "$bin_dir/.ue-wwan-status.XXXXXXXX")
    trap 'rm -f -- "$temp_file"' EXIT
    stamp "$temp_file"
    if ((EUID == 0)); then
        chown root:root -- "$temp_file"
    fi
    mv -fT -- "$temp_file" "$bin_dir/ue-wwan-status"
    printf 'Installed: %s/ue-wwan-status (version %s)\n' "$bin_dir" "$version"
    exit 0
fi

ssh_opts=(-o ConnectTimeout=10)
temp_file=$(mktemp "${TMPDIR:-/tmp}/ue-wwan-status.XXXXXXXX")
trap 'rm -f -- "$temp_file"' EXIT
stamp "$temp_file"

remote_tmp=$(ssh "${ssh_opts[@]}" -- "$host" 'mktemp /tmp/ue-wwan-status.XXXXXXXX')
if [[ ! "$remote_tmp" =~ ^/tmp/ue-wwan-status\.[A-Za-z0-9]+$ ]]; then
    echo "Error: unexpected remote temporary file: $remote_tmp" >&2
    exit 1
fi
scp -q "${ssh_opts[@]}" -- "$temp_file" "$host:$remote_tmp"

# Install beside the target, then rename, so running copies never see a partial file.
install_cmd="sh -c 'install -m 0755 -o root -g root -- $remote_tmp $dest.new && mv -fT $dest.new $dest'"
if ! ssh "${ssh_opts[@]}" -- "$host" "sudo -n $install_cmd"; then
    printf 'Copied version %s to %s:%s, but sudo there needs a password.\n' "$version" "$host" "$remote_tmp" >&2
    echo 'Finish the install with:' >&2
    printf "  ssh -t %s \"sudo %s && rm -f %s && %s --version\"\n" "$host" "$install_cmd" "$remote_tmp" "$dest" >&2
    exit 3
fi
ssh "${ssh_opts[@]}" -- "$host" "rm -f -- $remote_tmp"

installed=$(ssh "${ssh_opts[@]}" -- "$host" "$dest --version")
printf 'Installed: %s:%s (version %s)\n' "$host" "$dest" "$version"
if [[ "$installed" != "ue-wwan-status $version" ]]; then
    printf 'Error: %s reports "%s"\n' "$host" "$installed" >&2
    exit 1
fi
echo 'Runtime requirements on the UE host: Python 3, iproute2, and ping with ICMP permissions.'

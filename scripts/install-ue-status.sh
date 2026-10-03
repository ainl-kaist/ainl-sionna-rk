#!/usr/bin/env bash
# Install a standalone ue-status command, independent of repository permissions.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: sudo ./scripts/install-ue-status.sh [--prefix DIR]

Install ue_status.py as DIR/bin/ue-status (default: /usr/local/bin/ue-status).
Run this installer again after updating ue_status.py to update the command.
The installed copy reports the checkout's commit with --version.
A custom writable prefix can be used without sudo.

Users need Python 3, Docker CLI, and access to the Docker daemon at runtime.
This installer does not change Docker permissions or group membership.
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
source_file="$script_dir/ue_status.py"
if [[ ! -r "$source_file" ]]; then
    echo "Error: cannot read $source_file" >&2
    exit 1
fi

# Read-only describe: optional locks off so sudo never rewrites .git/index as root.
version=$(GIT_OPTIONAL_LOCKS=0 git -C "$script_dir" describe --always --dirty 2>/dev/null) || version=unknown
if [[ ! "$version" =~ ^[A-Za-z0-9._-]+$ ]]; then
    version=unknown
fi

bin_dir="${prefix%/}/bin"
if [[ "$bin_dir" == /usr/local/bin && $EUID -ne 0 ]]; then
    echo 'Error: run this installer with sudo to install for all users.' >&2
    exit 1
fi

install -d -m 0755 -- "$bin_dir"
# Replace the directory entry atomically, including any old symlink, without
# writing through it into a developer checkout.
temp_file=$(mktemp "$bin_dir/.ue-status.XXXXXXXX")
trap 'rm -f -- "$temp_file"' EXIT
sed "s/^__version__ = .*/__version__ = '$version'/" -- "$source_file" >"$temp_file"
if ! grep -qxF -- "__version__ = '$version'" "$temp_file"; then
    echo "Error: no __version__ line to stamp in $source_file" >&2
    exit 1
fi
chmod 0755 -- "$temp_file"
if ((EUID == 0)); then
    chown root:root -- "$temp_file"
fi
mv -fT -- "$temp_file" "$bin_dir/ue-status"

printf 'Installed: %s/ue-status (version %s)\n' "$bin_dir" "$version"
printf 'Ensure %s is in PATH, then run: ue-status\n' "$bin_dir"
echo 'Runtime requirements: Python 3, Docker CLI, and Docker daemon access.'

#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Stop and remove the EXTRA soft-UEs started by start_ues.sh (oai-nr-ue2,
# oai-nr-ue3, ...). The primary oai-nr-ue and the rest of the system are left
# running. Use stop_ue.sh for the primary UE.
#
# Usage:
#   ./scripts/stop_ues.sh        # remove all oai-nr-ue<N> for N>=2

set -euo pipefail

# Extra UEs are plain `docker run` containers (not compose services), so remove
# them directly. Match oai-nr-ue2, oai-nr-ue3, ... but NOT the primary oai-nr-ue.
mapfile -t extras < <(docker ps -a --format '{{.Names}}' \
                      | grep -E '^oai-nr-ue[0-9]+$' | sort)

if (( ${#extras[@]} == 0 )); then
    echo "No extra UEs (oai-nr-ue<N>) found."
    exit 0
fi

for name in "${extras[@]}"; do
    echo "Removing $name"
    docker rm -f "$name" >/dev/null 2>&1 || true
done

echo "Removed: ${extras[*]}"

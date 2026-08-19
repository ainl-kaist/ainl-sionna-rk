#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Stop ONLY the soft-UE container, leaving the 5G core and gNB running.
# Counterpart to start_ue.sh: handy for detaching/reattaching just the UE
# (e.g. while debugging the rfsim UE, or to pause traffic) without tearing
# down the rest of the system.
#
# Usage:
#   ./scripts/stop_ue.sh [config]   # config defaults to "rfsim"
#
# It uses the same per-config .env as start_ue.sh (config/<config>/.env).
# This issues `docker compose stop` (not `down`), so the container is kept and
# can be brought back with start_ue.sh. Because the UE has a
# `restart: unless-stopped` policy, a manual stop is honoured -- it will NOT
# auto-restart until you run start_ue.sh again.

set -e

# suppress outputs from pushd and popd
function pushd() { command pushd "$@" > /dev/null; }
function popd()  { command popd  "$@" > /dev/null; }

# defaults
CONFIG_NAME=${1:-rfsim}
configs_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../config")
env_file="${configs_dir}/${CONFIG_NAME}/.env"

if [[ ! -f "$env_file" ]]; then
    echo "Error: .env file not found at $env_file"
    echo "Usage: $0 [rfsim|b200|...]"
    exit 1
fi

if ! docker inspect -f '{{.State.Running}}' oai-nr-ue 2>/dev/null | grep -q true; then
    echo "oai-nr-ue is not running; nothing to stop."
    exit 0
fi

pushd "${configs_dir}/common"

echo "Using config: $CONFIG_NAME (env: $env_file)"
echo "Stopping nr-ue"
docker compose --env-file "$env_file" stop oai-nr-ue

popd

echo "oai-nr-ue stopped. Bring it back with: ./scripts/start_ue.sh ${CONFIG_NAME}"

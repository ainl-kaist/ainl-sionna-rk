#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Start (or restart) ONLY the soft-UE container, leaving the 5G core and gNB
# running. Handy because the OAI rfsim UE in this build occasionally aborts
# (buffer overflow) and needs to be brought back up on its own.
#
# Usage:
#   ./scripts/start_ue.sh [config]   # config defaults to "rfsim"
#
# It uses the same per-config .env as start_system.sh (config/<config>/.env),
# waits for the container to become healthy, and waits for the data-plane
# tunnel (oaitun_ue1) to get an IP so the UE is actually ready for traffic.

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

# The gNB must be up for the UE's rfsimulator client to connect.
if ! docker inspect -f '{{.State.Running}}' oai-gnb 2>/dev/null | grep -q true; then
    echo "Warning: oai-gnb is not running. The UE will keep retrying to connect"
    echo "         to the rfsim server. Start the full system with:"
    echo "             ./scripts/start_system.sh ${CONFIG_NAME}"
fi

pushd "${configs_dir}/common"

echo "Using config: $CONFIG_NAME (env: $env_file)"
echo "Starting nr-ue"
docker compose --env-file "$env_file" up -d oai-nr-ue

popd

# Wait until the container reports healthy.
timeout=90
start_time=$(date +%s)
echo "Waiting for oai-nr-ue to be healthy (Timeout: ${timeout}s)..."
while true; do
    status=$(docker inspect --format='{{.State.Health.Status}}' oai-nr-ue 2>/dev/null || echo "not_found")
    if [[ "$status" == "healthy" ]]; then
        echo "oai-nr-ue is healthy."
        break
    elif [[ "$status" == "not_found" ]]; then
        echo "Error: Container oai-nr-ue not found! Exiting..."
        exit 1
    fi
    if (( $(date +%s) - start_time >= timeout )); then
        echo "Error: Timeout waiting for oai-nr-ue to be healthy."
        exit 1
    fi
    sleep 2
done

# Wait for the data-plane tunnel (oaitun_ue1) to get an IP -> UE attached.
echo "Waiting for the UE tunnel (oaitun_ue1) to come up..."
ue_ip=""
start_time=$(date +%s)
while true; do
    ue_ip=$(docker exec oai-nr-ue ip -4 addr show oaitun_ue1 2>/dev/null \
            | grep -oP 'inet\s+\K[\d.]+' || true)
    [[ -n "$ue_ip" ]] && break
    if (( $(date +%s) - start_time >= 60 )); then
        echo "Warning: tunnel still down after 60s. The UE may still be attaching;"
        echo "         check 'docker logs oai-nr-ue'."
        exit 0
    fi
    sleep 2
done

echo "UE is up and connected (oaitun_ue1 = ${ue_ip})."

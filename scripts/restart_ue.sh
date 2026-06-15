#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Restart ONLY the soft-UE container, leaving the 5G core and gNB running.
# Thin wrapper that runs stop_ue.sh then start_ue.sh, so the UE detaches and
# reattaches cleanly without tearing down the rest of the system. Handy when
# the OAI rfsim UE in this build aborts (buffer overflow) or after changing
# the channel model, when the UE needs a fresh attach.
#
# Usage:
#   ./scripts/restart_ue.sh [config]   # config defaults to "rfsim"
#
# It just forwards the config to stop_ue.sh / start_ue.sh, which use the same
# per-config .env (config/<config>/.env) as start_system.sh. start_ue.sh waits
# for the container to be healthy and for the data-plane tunnel (oaitun_ue1) to
# get an IP, so on success the UE is ready for traffic.

set -e

CONFIG_NAME=${1:-rfsim}
script_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")

echo "=== Restarting UE (config: $CONFIG_NAME) ==="

echo "--- stop ---"
"${script_dir}/stop_ue.sh" "$CONFIG_NAME"

echo "--- start ---"
"${script_dir}/start_ue.sh" "$CONFIG_NAME"

echo "=== UE restart complete ==="

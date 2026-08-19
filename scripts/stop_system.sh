#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
set -e  # Stop script on any error

configs_dir=$(realpath $(dirname "${BASH_SOURCE[0]}")/../config)

echo "Shutting down single-gNB stack"
( cd "${configs_dir}/common" && docker compose down )

echo "Shutting down handover stack"
( cd "${configs_dir}/rfsim-ho" && ./start_handover.sh down )

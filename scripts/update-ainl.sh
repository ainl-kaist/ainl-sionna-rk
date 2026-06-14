#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 AINL. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Regenerate the auto-maintained "Changed files" region of AINL.md from git.
#
# It lists every file that differs from the NVlabs base commit (AINL_BASE,
# default fa405b8 = sionna-rk v1.2.0), using the staged index so it is accurate
# when invoked from the pre-commit hook (and equals base..HEAD when nothing is
# staged, for ad-hoc manual runs).
#
# Only the text between the markers is touched:
#     <!-- AUTO:files start -->  ...  <!-- AUTO:files end -->
#
# Usage:  scripts/update-ainl.sh            # refresh AINL.md in place
#         AINL_BASE=<sha> scripts/update-ainl.sh

set -euo pipefail

BASE="${AINL_BASE:-fa405b8}"
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 0; }
ainl="${repo}/AINL.md"

[ -f "$ainl" ] || { echo "AINL.md not found; nothing to do" >&2; exit 0; }
git cat-file -e "${BASE}^{commit}" 2>/dev/null || { echo "base $BASE not found; skipping" >&2; exit 0; }

# Build the file list: base vs index (= what this commit will contain). Exclude
# AINL.md itself so the doc doesn't list itself.
listfile="$(mktemp)"
git diff --cached --name-status "$BASE" -- . ':(exclude)AINL.md' 2>/dev/null \
  | awk -F'\t' '{
        c = substr($1, 1, 1)
        name = (c == "R" || c == "C") ? $3 : $2
        label = (c=="A")?"added":(c=="M")?"modified":(c=="D")?"deleted": \
                (c=="R")?"renamed":(c=="C")?"copied":c
        printf "- `%s` — %s\n", name, label
    }' > "$listfile"
[ -s "$listfile" ] || printf '_(no changes vs %s yet)_\n' "$BASE" > "$listfile"

# Splice the generated list between the AUTO markers.
tmp="$(mktemp)"
awk -v lf="$listfile" '
    /<!-- AUTO:files start -->/ {
        print
        while ((getline line < lf) > 0) print line
        close(lf)
        skip = 1
        next
    }
    /<!-- AUTO:files end -->/ { skip = 0 }
    skip != 1 { print }
' "$ainl" > "$tmp"
mv "$tmp" "$ainl"
rm -f "$listfile"

echo "AINL.md: Changed files region updated (base $BASE)."

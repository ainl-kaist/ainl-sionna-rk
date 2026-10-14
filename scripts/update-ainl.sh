#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 AINL. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Regenerate the auto-maintained "Changed files" region of AINL.md (English)
# and AINL.ko.md (Korean) from git.
#
# It lists every file that differs from the NVlabs base commit (AINL_BASE,
# default fa405b8 = sionna-rk v1.2.0), using the staged index so it is accurate
# when invoked from the pre-commit hook (and equals base..HEAD when nothing is
# staged, for ad-hoc manual runs).
#
# Only the text between the markers is touched:
#     <!-- AUTO:files start -->  ...  <!-- AUTO:files end -->
#
# Usage:  scripts/update-ainl.sh            # refresh AINL.md / AINL.ko.md in place
#         AINL_BASE=<sha> scripts/update-ainl.sh

set -euo pipefail

BASE="${AINL_BASE:-fa405b8}"
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 0; }

git cat-file -e "${BASE}^{commit}" 2>/dev/null || { echo "base $BASE not found; skipping" >&2; exit 0; }

# Build the file list (path<TAB>status letter): base vs index (= what this
# commit will contain). Exclude the AINL files themselves so they don't list
# themselves.
changes="$(mktemp)"
git diff --cached --name-status "$BASE" -- . ':(exclude)AINL.md' ':(exclude)AINL.ko.md' 2>/dev/null \
  | awk -F'\t' '{
        c = substr($1, 1, 1)
        name = (c == "R" || c == "C") ? $3 : $2
        print name "\t" c
    }' > "$changes"

# Splice the list, labelled in the file's language, between the AUTO markers.
update() {
    local doc="$1" lang="$2"
    [ -f "$doc" ] || { echo "${doc##*/} not found; skipping" >&2; return 0; }
    local listfile tmp
    listfile="$(mktemp)"
    awk -F'\t' -v lang="$lang" '{
            c = $2
            if (lang == "ko")
                label = (c=="A")?"추가":(c=="M")?"수정":(c=="D")?"삭제": \
                        (c=="R")?"이름 변경":(c=="C")?"복사":c
            else
                label = (c=="A")?"added":(c=="M")?"modified":(c=="D")?"deleted": \
                        (c=="R")?"renamed":(c=="C")?"copied":c
            printf "- `%s` — %s\n", $1, label
        }' "$changes" > "$listfile"
    if [ ! -s "$listfile" ]; then
        if [ "$lang" = ko ]; then
            printf '_(아직 %s 대비 변경 없음)_\n' "$BASE" > "$listfile"
        else
            printf '_(no changes vs %s yet)_\n' "$BASE" > "$listfile"
        fi
    fi
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
    ' "$doc" > "$tmp"
    mv "$tmp" "$doc"
    rm -f "$listfile"
    echo "${doc##*/}: Changed files region updated (base $BASE)."
}
update "${repo}/AINL.md"    en
update "${repo}/AINL.ko.md" ko
rm -f "$changes"

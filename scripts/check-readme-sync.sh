#!/bin/bash
#
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 AINL. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Check that scripts/README.md (English) and scripts/README.ko.md (Korean) have
# the same structure, so an edit made to one is not forgotten in the other.
# Any other English/Korean pair (e.g. AINL.md / AINL.ko.md) can be given as
# arguments.
#
# Compared, in order: heading levels, script entries (`- **`name`**` or
# `- **[name](link)**`), and the
# commands inside fenced code blocks with comments stripped (comments are
# translated, commands are not). Prose and translation quality are not checked.
#
# Usage:  scripts/check-readme-sync.sh                 # compare the working tree
#         scripts/check-readme-sync.sh <en.md> <ko.md> # compare given files
# Exit:   0 in sync, 1 out of sync (diff printed), 2 usage error.

set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
en="${1:-$dir/README.md}"
ko="${2:-$dir/README.ko.md}"

for f in "$en" "$ko"; do
    [ -f "$f" ] || { echo "not found: $f" >&2; exit 2; }
done

# Print one line per structural element of a Markdown file.
signature() {
    awk '
        /^[[:space:]]*```/ {
            infence = !infence
            sub(/^[[:space:]]+/, "")
            print "fence " $0
            next
        }
        infence {
            if ($0 ~ /^[[:space:]]*#/) next     # full-line comment
            sub(/[[:space:]]+#.*$/, "")         # trailing comment
            sub(/[[:space:]]+$/, "")
            if ($0 != "") print "code  " $0
            next
        }
        /^#+ / {
            match($0, /^#+/)
            print "head  h" RLENGTH
            next
        }
        /^- \*\*`[^`]+`\*\*/ {
            match($0, /`[^`]+`/)
            print "entry " substr($0, RSTART, RLENGTH)
            next
        }
        /^- \*\*\[[^]]+\]\(/ {
            match($0, /\[[^]]+\]/)
            print "entry " substr($0, RSTART, RLENGTH)
        }
    ' "$1"
}

if out="$(diff -u --label "en: $en" --label "ko: $ko" \
               <(signature "$en") <(signature "$ko"))"; then
    exit 0
fi

echo "$(basename "$en") and $(basename "$ko") are out of sync:" >&2
echo "$out" >&2
echo "Update both files in the same commit (see scripts/README.md, §8)." >&2
exit 1

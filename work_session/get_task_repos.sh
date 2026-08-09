#!/usr/bin/env bash
#
# Prints the repositories named in a task page's Source Repository field, one per
# line, most significant first - so the first line is the task's main repository.
#
# The field is written in two forms, both of which occur:
#     - **Source Repository**: shell-ui
#     - **Source Repository**:
#         - layout-service (branch: feature/...)
#
# Usage: get_task_repos.sh <task-page-path>

set -uo pipefail

page="${1:-}"

if [[ -z "$page" ]]; then
    echo "Usage: $(basename "$0") <task-page-path>" >&2
    exit 1
fi

if [[ ! -f "$page" ]]; then
    echo "Error: no such page: $page" >&2
    exit 1
fi

awk '
    /\*\*Source Repository\*\*:/ {
        match($0, /^[\t ]*/); base = RLENGTH
        rest = $0
        sub(/^.*\*\*Source Repository\*\*:[ \t]*/, "", rest)
        if (rest != "") { print rest; exit }
        in_list = 1
        next
    }
    in_list {
        match($0, /^[\t ]*/); indent = RLENGTH
        if (indent <= base) exit          # dedented back to a sibling field
        line = $0
        sub(/^[\t ]*-[ \t]*/, "", line)
        if (line != "") print line
    }
' "$page" | sed -E 's/[[:space:]]*\(branch:[^)]*\)[[:space:]]*$//; s/[[:space:]]+$//' | grep -v '^$'

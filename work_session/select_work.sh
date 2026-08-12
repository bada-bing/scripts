#!/usr/bin/env bash
#
# Picks what to work on: a pending task, or a repository with no task attached.
# Both kinds live in one list, because narrowing to the wrong kind first is how
# you miss the thing you wanted.
#
# Tasks named in today's hint sort first, so the list opens on what the day was
# planned around without hiding everything else. The hint carries no state - being
# named in it is the whole of what it says.
#
# Prints the selection as two tab-separated fields, "task <key>" or
# "repo <path>", and nothing at all when the picker is dismissed.
#
# Usage: select_work.sh [--tasks]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# --tasks drops the repositories: focus starts a task, so offering something it
# cannot start would only be a way to pick wrong.
tasks_only=false
[[ "${1:-}" == "--tasks" ]] && tasks_only=true

tasks() {
    local planned
    planned=$(mktemp) || return 1
    "$SCRIPT_DIR/journal_work_block.sh" list 2>/dev/null \
        | awk -F'\t' '$2 != "" { print $2 }' > "$planned"

    task status:pending export 2>/dev/null \
        | jq -r 'sort_by(-.urgency) | .[] | [.description, (.project // "-")] | @tsv' \
        | while IFS=$'\t' read -r key project; do
            page=$(basename "$(ls "$LOGSEQ_GRAPH_PATH/pages/$key"-*.md 2>/dev/null | head -1)" .md 2>/dev/null)
            if grep -qxF "$key" "$planned" 2>/dev/null; then
                rank=0; hint="hint"
            else
                rank=1; hint="-"
            fi
            printf '%s\ttask\t%s\t%s\t%s\t%s\n' \
                "$rank" "$hint" "$key" "$project" "${page#"$key"-}"
        done
    rm -f "$planned"
}

repos() {
    local roots
    IFS=':' read -ra roots <<< "${SRC_PATH:-$HOME/Developer/src}"
    find "${roots[@]}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort \
        | while read -r path; do
            printf '2\trepo\t%s\t%s\t%s\t%s\n' "-" "$(basename "$path")" "" "$path"
        done
}

# -s keeps urgency order within a rank; the rank column is dropped before display.
selection=$(
    { tasks; $tasks_only || repos; } \
        | sort -s -k1,1n \
        | awk -F'\t' '{ printf "%-5s %-6s %-30s %-6s %s\n", $2, $3, $4, $5, $6 }' \
        | fzf --height=60% --reverse --prompt="$($tasks_only && echo 'task> ' || echo 'work> ')"
)

[[ -z "$selection" ]] && exit 0

# Kind is field 1 and the hint flag field 2, so a task key is field 3; a
# repository's path is the last field, which survives its project column being
# empty. Neither may contain whitespace, which holds for keys and source roots.
kind=$(awk '{print $1}' <<< "$selection")
case "$kind" in
    task) printf 'task\t%s\n' "$(awk '{print $3}'  <<< "$selection")" ;;
    repo) printf 'repo\t%s\n' "$(awk '{print $NF}' <<< "$selection")" ;;
    *)    exit 1 ;;
esac

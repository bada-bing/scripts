#!/usr/bin/env bash
#
# Picks what to work on: a pending task, or a repository with no task attached.
# Both kinds live in one list, because narrowing to the wrong kind first is how
# you miss the thing you wanted.
#
# Tasks planned for today sort first, so the list opens on what the day was
# planned around without hiding everything else. "# Plan" carries no state, so
# being named there is the whole of what it says to the tooling.
#
# A marker written by hand is shown back - "planned later", "planned now" - but
# only shown: it does not order the list and it cannot refuse a start. The three
# words the journal reader recognises are LATER, NOW and DONE; anything else stays
# part of the entry's text.
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
    local planned_keys
    planned_keys=$(mktemp) || return 1
    "$SCRIPT_DIR/journal_work_block.sh" list 2>/dev/null \
        | awk -F'\t' '$2 != "" { print $2 "\t" $1 }' > "$planned_keys"

    task status:pending export 2>/dev/null \
        | jq -r 'sort_by(-.urgency) | .[] | [.description, (.project // "-")] | @tsv' \
        | while IFS=$'\t' read -r key project; do
            page=$(basename "$(ls "$LOGSEQ_GRAPH_PATH/pages/$key"-*.md 2>/dev/null | head -1)" .md 2>/dev/null)
            planned=$(awk -F'\t' -v k="$key" '
                $1 == k { print "planned" (length($2) ? " " tolower($2) : ""); found = 1; exit }
                END     { if (!found) print "-" }
            ' "$planned_keys")
            [[ "$planned" == "-" ]] && rank=1 || rank=0
            printf '%s\ttask\t%s\t%-5s %-14s %-30s %-6s %s\n' \
                "$rank" "$key" "task" "$planned" "$key" "$project" "${page#"$key"-}"
        done
    rm -f "$planned_keys"
}

repos() {
    local roots
    IFS=':' read -ra roots <<< "${SRC_PATH:-$HOME/Developer/src}"
    find "${roots[@]}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort \
        | while read -r path; do
            printf '2\trepo\t%s\t%-5s %-14s %-30s %-6s %s\n' \
                "$path" "repo" "-" "$(basename "$path")" "" "$path"
        done
}

# Four tab-separated fields: rank, kind, what to return, and the line to show.
# fzf displays only the fourth and hands the whole line back, so the answer is
# read from a field of its own rather than parsed out of the formatting. Display
# columns can then hold anything, spaces included, without breaking the result.
# -s keeps urgency order within a rank.
selection=$(
    { tasks; $tasks_only || repos; } \
        | sort -s -k1,1n \
        | fzf --height=60% --reverse --delimiter='\t' --with-nth=4 \
              --prompt="$($tasks_only && echo 'task> ' || echo 'work> ')"
)

[[ -z "$selection" ]] && exit 0

kind=$(awk -F'\t' '{print $2}' <<< "$selection")
answer=$(awk -F'\t' '{print $3}' <<< "$selection")
case "$kind" in
    task|repo) printf '%s\t%s\n' "$kind" "$answer" ;;
    *)         exit 1 ;;
esac

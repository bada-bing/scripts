#!/usr/bin/env bash
#
# Picks what to work on: a pending task, or a repository with no task attached.
# Both kinds live in one list, because narrowing to the wrong kind first is how
# you miss the thing you wanted.
#
# Prints the selection as two tab-separated fields, "task <key>" or
# "repo <path>", and nothing at all when the picker is dismissed.
#
# Usage: select_work.sh

set -uo pipefail

LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# --tasks drops the repositories: focus starts a task, so offering something it
# cannot start would only be a way to pick wrong.
tasks_only=false
[[ "${1:-}" == "--tasks" ]] && tasks_only=true

# Tasks first, most urgent first - a task is the usual reason to open a session.
tasks() {
    task status:pending export 2>/dev/null \
        | jq -r 'sort_by(-.urgency) | .[] | [.description, (.project // "-")] | @tsv' \
        | while IFS=$'\t' read -r key project; do
            page=$(basename "$(ls "$LOGSEQ_GRAPH_PATH/pages/$key"-*.md 2>/dev/null | head -1)" .md 2>/dev/null)
            printf 'task\t%s\t%s\t%s\n' "$key" "$project" "${page#"$key"-}"
        done
}

repos() {
    local roots
    IFS=':' read -ra roots <<< "${SRC_PATH:-$HOME/Developer/src}"
    find "${roots[@]}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort \
        | while read -r path; do
            printf 'repo\t%s\t%s\t%s\n' "$(basename "$path")" "" "$path"
        done
}

selection=$(
    { tasks; $tasks_only || repos; } \
        | awk -F'\t' '{ printf "%-5s %-30s %-6s %s\n", $1, $2, $3, $4 }' \
        | fzf --height=60% --reverse --prompt="$($tasks_only && echo 'task> ' || echo 'work> ')"
)

[[ -z "$selection" ]] && exit 0

# The task key is field 2; a repository's path is the last field, which survives
# the project column being empty for repositories. Neither may contain
# whitespace, which holds for task keys and for the source roots.
kind=$(awk '{print $1}' <<< "$selection")
case "$kind" in
    task) printf 'task\t%s\n' "$(awk '{print $2}'  <<< "$selection")" ;;
    repo) printf 'repo\t%s\n' "$(awk '{print $NF}' <<< "$selection")" ;;
    *)    exit 1 ;;
esac

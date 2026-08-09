#!/usr/bin/env bash
#
# Resolves a task key to its Logseq page.
#
# Task pages are named <KEY>-<kebab-title>.md, so the key is matched anchored at
# the start rather than as a substring - otherwise WFC-114 would resolve
# WFC-1146's page. Prints exactly one path; an ambiguous match is an error, not
# a silent first hit.
#
# Usage: find_task_page.sh <task-key>

set -uo pipefail

task_key="${1:-}"

if [[ -z "$task_key" ]]; then
    echo "Usage: $(basename "$0") <task-key>" >&2
    exit 1
fi

LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"
pages_dir="$LOGSEQ_GRAPH_PATH/pages"

# Both page forms are allowed, with and without a title suffix. nullglob drops a
# wildcard pattern that matches nothing, but it does not apply to a path with no
# wildcard in it - so the suffix-less form is tested with -f instead, or it would
# count as a match even when the file does not exist.
matches=()
[[ -f "$pages_dir/$task_key.md" ]] && matches+=("$pages_dir/$task_key.md")
shopt -s nullglob
matches+=("$pages_dir/$task_key"-*.md)
shopt -u nullglob

case ${#matches[@]} in
    0)
        echo "Error: no Logseq page for task '$task_key' in $pages_dir" >&2
        exit 1
        ;;
    1)
        echo "${matches[0]}"
        ;;
    *)
        echo "Error: ambiguous, ${#matches[@]} pages match task '$task_key'" >&2
        printf '  %s\n' "${matches[@]}" >&2
        exit 1
        ;;
esac

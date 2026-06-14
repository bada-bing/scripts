#!/bin/bash

set -e

usage() {
    echo "Usage: $(basename "$0") <project>" >&2
}

PROJECT="${1:-}"

if [[ -z "$PROJECT" ]]; then
    usage
    exit 1
fi

if [[ "$PROJECT" == "-h" || "$PROJECT" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! "$PROJECT" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Error: project must contain only letters, numbers, dots, underscores, or hyphens." >&2
    exit 1
fi

HEADER=$'DESC\tURG\tPRIO\tDUE\tSUMMARY'
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# Get all potential task files once to avoid looping `find`.
LOGSEQ_FILES=$(find "$LOGSEQ_GRAPH_PATH/pages" -type f -name "*.md")

generate_task_lines() {
    task "project:$PROJECT" -backlog export | \
    jq -c 'sort_by(.urgency) | reverse | .[] | select(.status == "pending")' | \
    while read -r line; do
        description=$(echo "$line" | jq -r '.description')
        summary_path=$(echo "$LOGSEQ_FILES" | grep -F --max-count=1 "$description" || true)

        echo "$line" | jq -r --arg summary "$(basename "$summary_path" .md 2>/dev/null)" \
            '[.description, (.urgency | round), (.priority // "_"), (if .due then (.due | strptime("%Y%m%dT%H%M%SZ") | strftime("%Y-%m-%d")) else "_" end), ($summary | if . == "" then "_" else . end)] | @tsv'
    done
}

TASKS=$(generate_task_lines)

SELECTED_LINE=$(printf '%s\n%s\n' "$HEADER" "$TASKS" | fzf --header-lines=1 --height=40% --reverse || true)

if [[ -n "$SELECTED_LINE" ]]; then
    printf '%s\n' "$SELECTED_LINE" | awk -F $'\t' '{print $1}'
fi

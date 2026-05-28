#!/bin/bash
#
# Header for the table
HEADER=$'DESC\tURG\tPRIO\tDUE\tSUMMARY'

# Get all potential task files ONCE to avoid looping `find`
LOGSEQ_FILES=$(find /Users/miki/Documents/Logseq/KB/pages/ -type f -name "*.md")

# Process tasks and generate lines for fzf
generate_task_lines() {
    task project:study -backlog export | \
    jq -c 'sort_by(.urgency) | reverse | .[] | select(.status == "pending")' | \
    while read -r line; do
        # Use a single jq call to parse the description for use with grep
        description=$(echo "$line" | jq -r '.description')

        # Grep the in-memory list of files instead of calling an external script. This is much faster.
        summary_path=$(echo "$LOGSEQ_FILES" | grep -F --max-count=1 "$description")
        
        # Use jq to parse the rest of the fields and combine with the summary
        echo "$line" | jq -r --arg summary "$(basename "$summary_path" .md 2>/dev/null)" \
            '[.description, (.urgency | round), (.priority // "_"), (if .due then (.due | strptime("%Y%m%dT%H%M%SZ") | strftime("%Y-%m-%d")) else "_" end), ($summary | if . == "" then "_" else . end)] | @tsv'
    done
}

TASKS=$(generate_task_lines)

# Combine header and tasks, format as a table, then pipe to fzf
# Using @tsv from jq makes `column -t` work correctly with tabs.
SELECTED_LINE=$( (echo "$HEADER"; echo "$TASKS") | column -t -s $'\t' | fzf --header-lines=1 --height=40% --reverse || true)

# If a selection was made, extract the first column (description) and output it
if [[ -n "$SELECTED_LINE" ]]; then
    echo "$SELECTED_LINE" | awk '{print $1}'
fi
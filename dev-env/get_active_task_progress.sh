#!/usr/bin/env bash

# Prints the active Taskwarrior task for the tmux status bar, including
# the current NOW item from a matching Logseq page when one exists.

# Ensure node is in the PATH for the tmux environment
NODE_BIN_DIR="$(dirname "$(/opt/homebrew/bin/mise which node 2>/dev/null)")"
export PATH="$NODE_BIN_DIR:$PATH"

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# 1. Get the active task description from taskwarrior
TASK_DESCRIPTION=$("$script_dir/../taskwarrior/get_active_task_description.sh")

# 2. Handle case where there is no active task
if [ -z "$TASK_DESCRIPTION" ]; then
    echo "  NO ACTIVE TASK"
    exit 0
fi

# 3. We have a task. This is our default output if no Logseq page is found.
FINAL_OUTPUT="Task $TASK_DESCRIPTION"

# 4. Try to find the corresponding file in Logseq
LOGSEQ_GRAPH_PATH="${LS_DIR:-$HOME/Documents/Logseq/KB}"

if [ ! -d "$LOGSEQ_GRAPH_PATH" ]; then
    echo "$FINAL_OUTPUT"
    exit 0
fi

LOGSEQ_FILE=$(find "$LOGSEQ_GRAPH_PATH/pages" -type f -iname "*$TASK_DESCRIPTION*.md" | head -n 1)

# 5. If a Logseq file is found, try to get detailed progress
if [ -n "$LOGSEQ_FILE" ]; then
    PROGRESS_OUTPUT=$("$script_dir/../tracking_task_progress/get_logseq_task_progress.js" "$LOGSEQ_FILE" 2>/dev/null)

    if [ -n "$PROGRESS_OUTPUT" ]; then
        STEP=$(echo "$PROGRESS_OUTPUT" | grep "Current Step:" | sed 's/.*Current Step: //')
        ACTIVE_ITEM=$(echo "$PROGRESS_OUTPUT" | grep "NOW:" | sed 's/.*- NOW: //')

        if [ -n "$STEP" ] && [ -n "$ACTIVE_ITEM" ]; then
            STEP_TRIMMED=$(echo "$STEP" | xargs)
            ACTIVE_ITEM_TRIMMED=$(echo "$ACTIVE_ITEM" | xargs)
            # If we found details, update the final output
            FINAL_OUTPUT="Task $TASK_DESCRIPTION ▶ Step $STEP_TRIMMED ┋ NOW $ACTIVE_ITEM_TRIMMED"
        fi
    fi
fi

# 6. Print the final result (either default task or detailed progress)
echo "$FINAL_OUTPUT"

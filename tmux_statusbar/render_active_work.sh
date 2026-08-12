#!/usr/bin/env bash

# Prints what is being recorded right now for the tmux status bar, including the
# current NOW item from a matching Logseq page when one exists.
#
# The identity comes from the open Timewarrior interval, not from Taskwarrior:
# the interval is the record of what is happening, and Taskwarrior no longer
# marks anything active.

# Ensure node is in the PATH for the tmux environment
NODE_BIN_DIR="$(dirname "$(/opt/homebrew/bin/mise which node 2>/dev/null)")"
export PATH="$NODE_BIN_DIR:$PATH"

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# 1. Get the identity of the interval being recorded
IDENTITY=$("$script_dir/../work_session/get_active_identity.sh")

# 2. Nothing being recorded, or something being recorded that cannot be named.
#    The two must not read alike: an unlabelled interval accrues time, and a bar
#    saying nothing is active while it runs is why it goes unnoticed.
if [ -z "$IDENTITY" ]; then
    if [ "$(timew get dom.active 2>/dev/null)" = "1" ]; then
        echo "  UNLABELLED WORK"
    else
        echo "  NO ACTIVE WORK"
    fi
    exit 0
fi

# 3. We have an identity. This is our default output if no Logseq page is found.
FINAL_OUTPUT="Task $IDENTITY"

# 4. Try to find the corresponding file in Logseq
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

if [ ! -d "$LOGSEQ_GRAPH_PATH" ]; then
    echo "$FINAL_OUTPUT"
    exit 0
fi

LOGSEQ_FILE=$(find "$LOGSEQ_GRAPH_PATH/pages" -type f -iname "*$IDENTITY*.md" | head -n 1)

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
            FINAL_OUTPUT="Task $IDENTITY ▶ Step $STEP_TRIMMED ┋ NOW $ACTIVE_ITEM_TRIMMED"
        fi
    fi
fi

# 6. Print the final result (either default task or detailed progress)
echo "$FINAL_OUTPUT"

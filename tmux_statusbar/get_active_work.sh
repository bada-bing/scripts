#!/usr/bin/env bash

# Prints what is being recorded right now, as fields for the status bar to
# compose. Nothing here decides how any of it looks: the bar is laid out
# against a width this script knows nothing about, so a sentence assembled
# here could only be cut blindly from the right.
#
# The output is always four tab-separated fields, empty where they do not
# apply, so a caller can take any of them with cut and never get the whole
# line back for want of a delimiter:
#
#   <kind>  <identity>  <step>  <now>
#
# kind is one of:
#
#   none        nothing is being recorded
#   unlabelled  an interval is open that carries no identity
#   adhoc       work with no task, the identity being its label
#   task        task work, the identity being the task key
#
# Nothing and unlabelled must not read alike: an unlabelled interval accrues
# time, and a bar saying nothing is active while it runs is why it goes
# unnoticed.
#
# step and now are filled only for task work, and only when a Logseq page for
# the key reports both a current step and an item marked NOW.
#
# The identity comes from the open Timewarrior interval, not from Taskwarrior:
# the interval is the record of what is happening, and Taskwarrior no longer
# marks anything active.

# Ensure node is in the PATH for the tmux environment
NODE_BIN_DIR="$(dirname "$(/opt/homebrew/bin/mise which node 2>/dev/null)")"
export PATH="$NODE_BIN_DIR:$PATH"

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

emit() {
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

# 1. What is being recorded, as "<kind>\t<identity>", or nothing at all.
ACTIVE=$("$script_dir/../work_session/get_active_identity.sh")
KIND=$(printf '%s' "$ACTIVE" | cut -f1)
IDENTITY=$(printf '%s' "$ACTIVE" | cut -f2)

# 2. Nothing being recorded, or something being recorded that cannot be named.
if [ -z "$IDENTITY" ]; then
    if [ "$(timew get dom.active 2>/dev/null)" = "1" ]; then
        emit unlabelled "" "" ""
    else
        emit none "" "" ""
    fi
    exit 0
fi

# 3. An adhoc has no page and no progress to read, so its label is the whole
#    answer.
if [ "$KIND" = "adhoc" ]; then
    emit adhoc "$IDENTITY" "" ""
    exit 0
fi

# 4. Task work. Without a Logseq page there is nothing beyond the key.
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

if [ ! -d "$LOGSEQ_GRAPH_PATH" ]; then
    emit task "$IDENTITY" "" ""
    exit 0
fi

LOGSEQ_FILE=$(find "$LOGSEQ_GRAPH_PATH/pages" -type f -iname "*$IDENTITY*.md" | head -n 1)

if [ -z "$LOGSEQ_FILE" ]; then
    emit task "$IDENTITY" "" ""
    exit 0
fi

# 5. The page's current step and the item marked NOW within it. Both or
#    neither: a step with no active item says nothing the key does not.
PROGRESS_OUTPUT=$("$script_dir/../tracking_task_progress/get_logseq_task_progress.js" "$LOGSEQ_FILE" 2>/dev/null)
STEP=$(echo "$PROGRESS_OUTPUT" | grep "Current Step:" | sed 's/.*Current Step: //' | xargs)
ACTIVE_ITEM=$(echo "$PROGRESS_OUTPUT" | grep "NOW:" | sed 's/.*- NOW: //' | xargs)

if [ -n "$STEP" ] && [ -n "$ACTIVE_ITEM" ]; then
    emit task "$IDENTITY" "$STEP" "$ACTIVE_ITEM"
else
    emit task "$IDENTITY" "" ""
fi

#!/bin/sh

# Prints today's tracked time from Timewarrior as H:MM.
# If there is an active Taskwarrior task, shows time for that task only.
# Falls back to total day time when no task is active.
# Outputs nothing if timewarrior is not installed or no time was tracked today.

TIMEW_BIN=$(command -v timew 2>/dev/null)
[ -z "$TIMEW_BIN" ] && exit 0

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ACTIVE_TASK=$("$SCRIPT_DIR/../taskwarrior/get_active_task_description.sh" 2>/dev/null)

if [ -n "$ACTIVE_TASK" ]; then
    total=$("$TIMEW_BIN" summary :day "$ACTIVE_TASK" 2>/dev/null | awk 'NF{last=$NF} END{print last}')
else
    total=$("$TIMEW_BIN" summary :day 2>/dev/null | awk 'NF{last=$NF} END{print last}')
fi

# Validate it looks like a duration (H:MM:SS or HH:MM:SS)
echo "$total" | grep -qE '^[0-9]+:[0-9]{2}:[0-9]{2}$' || exit 0

# Drop seconds for brevity
echo "$total" | cut -d: -f1,2

#!/bin/sh

# Prints today's total tracked time from Timewarrior as H:MM.
# Outputs nothing if timewarrior is not installed or no time was tracked today.

TIMEW_BIN=$(command -v timew 2>/dev/null)
[ -z "$TIMEW_BIN" ] && exit 0

total=$("$TIMEW_BIN" summary :day 2>/dev/null | awk 'NF{last=$NF} END{print last}')

# Validate it looks like a duration (H:MM:SS or HH:MM:SS)
echo "$total" | grep -qE '^[0-9]+:[0-9]{2}:[0-9]{2}$' || exit 0

# Drop seconds for brevity
echo "$total" | cut -d: -f1,2

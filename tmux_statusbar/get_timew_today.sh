#!/bin/sh

# Prints the status bar's time figure as H:MM [nT].
#
# While an interval is open the figure is that sitting - how long the current work
# has been running - which is the number that stops a timer being forgotten. With
# nothing open it falls back to the whole day's total.
#
# n counts the distinct identities recorded today: tags marked with a "%" prefix,
# plus the bare keys written before the prefix existed.
#
# Outputs nothing if timewarrior is not installed or no time was tracked today.

TIMEW_BIN=$(command -v timew 2>/dev/null)
[ -z "$TIMEW_BIN" ] && exit 0

total=""

# dom.active.json is an error rather than an empty answer when nothing is
# running, so the flag is tested first.
if [ "$("$TIMEW_BIN" get dom.active 2>/dev/null)" = "1" ]; then
    started=$("$TIMEW_BIN" get dom.active.start 2>/dev/null)
    started_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$started" '+%s' 2>/dev/null)
    if [ -n "$started_epoch" ]; then
        elapsed=$(( $(date '+%s') - started_epoch ))
        total=$(printf '%d:%02d:%02d' \
            $((elapsed / 3600)) $(((elapsed % 3600) / 60)) $((elapsed % 60)))
    fi
fi

[ -z "$total" ] && total=$("$TIMEW_BIN" summary :day 2>/dev/null | awk 'NF{last=$NF} END{print last}')

# Validate it looks like a duration (H:MM:SS or HH:MM:SS)
echo "$total" | grep -qE '^[0-9]+:[0-9]{2}:[0-9]{2}$' || exit 0

task_count=$("$TIMEW_BIN" export :day 2>/dev/null | jq -r '
    [ .[]
      | (   ([.tags[]? | select(startswith("%"))]                              | first)
         // ([.tags[]? | select(test("^[A-Za-z0-9]+[-_][0-9]+$"))]             | first)
         // empty
        )
      | ltrimstr("%")
    ] | unique | length' 2>/dev/null)
[ -z "$task_count" ] && task_count=0

# Drop seconds for brevity, append the identity count
printf "%s [%sT]\n" "$(echo "$total" | cut -d: -f1,2)" "$task_count"

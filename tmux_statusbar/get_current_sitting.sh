#!/bin/sh

# Prints how long the interval that is open now has been running, as H:MM, and
# nothing at all when nothing is being recorded.
#
# One meaning, always. This used to fall back to the day's total when nothing ran, so
# the same number in the same place was the current sitting at one moment and the
# whole day at another, with nothing to tell them apart. The count of things worked
# on went with it: it read as "1T", and T stopped being true the moment work with no
# task could be recorded.
#
# Printing nothing is what removes "⏱" from the bar too - render_right_side.sh omits
# the marker along with the value.
#
# dom.active.start is local and carries no zone, hence the format below.

TIMEW_BIN=$(command -v timew 2>/dev/null)
[ -z "$TIMEW_BIN" ] && exit 0

[ "$("$TIMEW_BIN" get dom.active 2>/dev/null)" = "1" ] || exit 0

started=$("$TIMEW_BIN" get dom.active.start 2>/dev/null)
[ -n "$started" ] || exit 0

started_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$started" '+%s' 2>/dev/null)
[ -n "$started_epoch" ] || exit 0

elapsed=$(( $(date '+%s') - started_epoch ))
[ "$elapsed" -lt 0 ] && exit 0

printf '%d:%02d\n' $((elapsed / 3600)) $(((elapsed % 3600) / 60))

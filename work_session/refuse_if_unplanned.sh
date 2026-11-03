#!/usr/bin/env bash
#
# Exits 0 when today is planned, and refuses with an explanation when it is not.
#
# Usage: refuse_if_unplanned.sh [<what>]
#
# No work other than planning starts before the day is planned. The day is planned
# once today's # Plan holds the planning chore marked DONE, which the assistant
# writes when it writes the plan I confirmed. Until then the planning chore is the
# only thing that starts, so <what> being that chore passes.
#
# A dropped planning chore (CANCELED) is not done, so it keeps the day closed.
#
# This is the one definition of that refusal, so the picker can decline before it
# asks a question rather than after, the same as refuse_if_recording.sh.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# The chore's text in [[SOA/Chores]], which is also the label its interval carries.
planning_chore="Plan the day"

[[ "${1:-}" == "$planning_chore" ]] && exit 0

"$SCRIPT_DIR/journal_work_block.sh" list 2>/dev/null \
    | awk -F'\t' -v chore="$planning_chore" '
        $1 == "DONE" && $4 == chore { found = 1 }
        END { exit !found }
    ' && exit 0

echo "Error: the day is not planned yet" >&2
printf "  to plan it: work start '%s'\n" "$planning_chore" >&2
exit 1

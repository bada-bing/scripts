#!/usr/bin/env bash
#
# Prints where the day stands: the time worked against the working time, and
# what comes next.
#
# Usage: report_day.sh
#
# The time worked is every interval recorded today, the open one up to now. The
# working time is the working-time:: property of [[SOA/Daily/DoD]].
#
# Nothing here is written anywhere. What comes next is the first item of today's
# # Plan that is not done or dropped for today and is not the current one, which
# is the open interval. Until the day is planned, what comes next
# is planning it.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# A duration as the journal writes it.
spell() {
    local h=$(( $1 / 60 )) m=$(( $1 % 60 ))
    if   [[ "$h" -eq 0 ]]; then printf '%dm' "$m"
    elif [[ "$m" -eq 0 ]]; then printf '%dh' "$h"
    else printf '%dh%02dm' "$h" "$m"
    fi
}

# Today's intervals, counted from midnight so one that crossed it counts only
# its part of today.
midnight=$(date -j -f '%Y-%m-%d %H:%M:%S' "$(date '+%Y-%m-%d') 00:00:00" '+%s')
now=$(date '+%s')
worked=$(timew export today 2>/dev/null | jq --argjson from "$midnight" --argjson now "$now" '
    def stamp: strptime("%Y%m%dT%H%M%SZ") | mktime;
    [.[] | ((if .end then (.end | stamp) else $now end)
            - ([(.start | stamp), $from] | max))]
    | map(select(. > 0)) | add // 0 | . / 60 | floor')

working=$(sed -n 's/^working-time:: *//p' "$LOGSEQ_GRAPH_PATH/pages/SOA%2FDaily%2FDoD.md" 2>/dev/null | head -1)
printf 'worked today: %s%s\n' "$(spell "$worked")" "${working:+ of $working}"

IFS=$'\t' read -r kind current <<< "$("$SCRIPT_DIR/get_active_identity.sh")"

if [[ "${current:-}" != "Plan the day" ]] && ! "$SCRIPT_DIR/refuse_if_unplanned.sh" 2>/dev/null; then
    echo "next: Plan the day"
    exit 0
fi

next=$("$SCRIPT_DIR/journal_work_block.sh" list 2>/dev/null \
    | awk -F'\t' -v cur="${current:-}" '
        $1 == "DONE" || $1 == "CANCELED" || $4 == "" { next }
        { what = ($2 != "" && $4 ~ /^\[\[/) ? $2 : $4 }
        what == cur { next }
        { print what; exit }')
printf 'next: %s\n' "${next:-nothing left in the plan}"

#!/usr/bin/env bash
#
# Annotates a day's "# Work" entries with what Timewarrior recorded for them:
# the number of sessions and the time they add up to, e.g. "2S (3h)".
#
# The journal says what was planned; this is the half that says what happened.
# Nothing here writes markers - that belongs to focus.sh.
#
# Re-running replaces the annotation rather than appending to it, so correcting
# an interval by hand and running this again fixes the journal.
#
# Usage: render_work_actuals.sh [YYYY-MM-DD] [--dry-run]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BLOCK="$SCRIPT_DIR/journal_work_block.sh"

day=""
dry_run=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run="--dry-run" ;;
        *)         day="$arg" ;;
    esac
done

day="${day:-$(date '+%Y-%m-%d')}"
if [[ ! "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Usage: $(basename "$0") [YYYY-MM-DD] [--dry-run]" >&2
    exit 1
fi
next_day=$(date -j -v+1d -f '%Y-%m-%d' "$day" '+%Y-%m-%d')

# "3h", "2h30m", "45m" - the shape used in the journal.
format_duration() {
    local total="$1" hours minutes
    hours=$((total / 3600))
    minutes=$(((total % 3600) / 60))
    if   ((hours > 0 && minutes > 0)); then printf '%dh%dm' "$hours" "$minutes"
    elif ((hours > 0));                then printf '%dh' "$hours"
    else                                    printf '%dm' "$minutes"
    fi
}

# An interval carries the task key plus domain tags (client_wpsm, job, ...), so
# the key is the tag shaped like one: letters or digits, a separator, a number.
# Timewarrior stamps times as 20260809T103000Z, which is not ISO 8601 as jq
# reads it, hence strptime rather than fromdateiso8601. An open interval is
# measured up to now, so a running task still reports what it has accumulated.
per_key=$(
    timew export "$day" - "$next_day" 2>/dev/null | jq -r '
        def key: [.tags[] | select(test("^[A-Za-z0-9]+[-_][0-9]+$"))] | first;
        def stamp: strptime("%Y%m%dT%H%M%SZ") | mktime;

        map({
            key: key,
            seconds: (((.end // (now | strftime("%Y%m%dT%H%M%SZ"))) | stamp) - (.start | stamp))
        })
        | group_by(.key)
        | map({ key: .[0].key, sessions: length, seconds: (map(.seconds) | add) })
        | .[] | [(.key // "-"), .sessions, .seconds] | @tsv
    '
)

if [[ -z "$per_key" ]]; then
    echo "No intervals recorded on $day" >&2
    exit 0
fi

while IFS=$'\t' read -r key sessions seconds; do
    [[ -z "$key" ]] && continue

    # Intervals tagged with nothing task-shaped cannot be placed in the journal.
    # Reported rather than dropped, so a missing annotation is never a mystery.
    if [[ "$key" == "-" ]]; then
        echo "Skipped $sessions interval(s) on $day carrying no task key" >&2
        continue
    fi

    # Time logged for something the day never planned means focus was bypassed.
    # Record it unmarked - it happened, it just was not planned - rather than
    # letting the record quietly omit real work.
    if ! "$BLOCK" list --date "$day" | cut -f2 | grep -qx "$key"; then
        "$BLOCK" set-marker "$key" - --date "$day" $dry_run
    fi

    annotation="${sessions}S ($(format_duration "$seconds"))"
    "$BLOCK" annotate "$key" "$annotation" --date "$day" $dry_run
    echo "$key: $annotation"
done <<< "$per_key"

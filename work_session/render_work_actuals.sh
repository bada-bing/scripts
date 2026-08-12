#!/usr/bin/env bash
#
# Renders a day's "# Work" block from Timewarrior - the day's record: one entry
# per task worked on, with the number of sessions and the time they add up to.
#
#   - [[WFC-1146-integrate-umami]] 2S (3h)
#
# One-way and machine-owned. The block is replaced whole on every run, so a
# corrected or deleted interval is reflected simply by running this again, and
# nothing hand-written survives there - intent belongs in "# Plan".
#
# Entries are ordered by when the work started, so the block reads as the day did.
#
# Usage: render_work_actuals.sh [YYYY-MM-DD] [--dry-run] [--work-file <path>]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BLOCK="$SCRIPT_DIR/journal_work_block.sh"

day=""
dry_run=false
work_file=""
owns_copy=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   dry_run=true; shift ;;
        --work-file) work_file="${2:-}"; shift 2 ;;
        *)           day="$1"; shift ;;
    esac
done

day="${day:-$(date '+%Y-%m-%d')}"
if [[ ! "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Usage: $(basename "$0") [YYYY-MM-DD] [--dry-run]" >&2
    exit 1
fi
next_day=$(date -j -v+1d -f '%Y-%m-%d' "$day" '+%Y-%m-%d')

# The day's edges in epoch seconds. Timewarrior stores UTC and a journal day is
# local, so these must be built from local midnight - reading them as UTC would
# shift every figure by the offset, which looks like a rounding error rather
# than a bug.
day_start=$(date -j -f '%Y-%m-%d %H:%M:%S' "$day 00:00:00" '+%s')
day_end=$(date -j -f '%Y-%m-%d %H:%M:%S' "$next_day 00:00:00" '+%s')

block_opts="--block Work --date $day"
if [[ -n "$work_file" ]]; then
    block_opts="$block_opts --work-file $work_file"
elif $dry_run; then
    work_file=$(mktemp -u "${TMPDIR:-/tmp}/render-actuals.XXXXXX")
    block_opts="$block_opts --work-file $work_file"
    owns_copy=true
    trap '[[ -n "$work_file" ]] && rm -f "$work_file"' EXIT
fi

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

# The identity - what makes two intervals the same piece of work - is the tag
# marked with a "%" prefix. A bare key is still accepted, matched by its shape:
# letters or digits, a separator, a number. Intervals written before the prefix
# existed carry that form, and they are not rewritten until the backfill.
#
# Timewarrior stamps times as 20260809T103000Z, which is not ISO 8601 as jq
# reads it, hence strptime rather than fromdateiso8601. An open interval is
# measured up to now, so a running task still reports what it has accumulated.
#
# Timewarrior has no concept of a day and returns an interval whole for every day
# it touches, so each one is clamped to the day being rendered - otherwise a
# 22:00 to 02:00 interval would count four hours on both days. An interval
# reaching past an edge is flagged, so the entry can say it continues.
per_key=$(
    timew export "$day" - "$next_day" 2>/dev/null | jq -r \
        --argjson ds "$day_start" --argjson de "$day_end" '
        def key:
            ([.tags[] | select(startswith("%"))] | first) as $identity
          | if $identity then ($identity | ltrimstr("%"))
            else ([.tags[] | select(test("^[A-Za-z0-9]+[-_][0-9]+$"))] | first)
            end;
        def stamp: strptime("%Y%m%dT%H%M%SZ") | mktime;

        map(
            (.start | stamp) as $s
          | (if .end then (.end | stamp) else (now | floor) end) as $e
          | {
                key:     key,
                start:   $s,
                seconds: (([$e, $de] | min) - ([$s, $ds] | max)),
                before:  ($s < $ds),
                after:   ($e > $de)
            }
        )
        # An interval ending exactly at midnight contributes nothing to the next
        # day, and a phantom 0m entry there would be a lie about working.
        | map(select(.seconds > 0))
        | group_by(.key)
        | map({
              key:      .[0].key,
              sessions: length,
              seconds:  (map(.seconds) | add),
              start:    (map(.start) | min),
              before:   (map(.before) | any),
              after:    (map(.after) | any)
          })
        | sort_by(.start)
        | .[] | [(.key // "-"), .sessions, .seconds, .before, .after] | @tsv
    '
)

# Built as whole lines, since the block is replaced rather than patched.
lines=()
while IFS=$'\t' read -r key sessions seconds before after; do
    [[ -z "$key" ]] && continue

    # Intervals tagged with nothing task-shaped have no entry to belong to.
    # Reported rather than dropped, so a missing line is never a mystery.
    if [[ "$key" == "-" ]]; then
        echo "Skipped $sessions interval(s) on $day carrying no task key" >&2
        continue
    fi

    page="$key"
    if page_path=$("$SCRIPT_DIR/find_task_page.sh" "$key" 2>/dev/null); then
        page=$(basename "$page_path" .md)
    fi

    annotation="${sessions}S ($(format_duration "$seconds"))"
    line="[[$page]] $annotation"

    # The arrows are for the reader: the figures are already right without them,
    # but a clamped 10m entry reads as wrong unless it says it continued.
    [[ "$before" == "true" ]] && line="→ $line"
    [[ "$after"  == "true" ]] && line="$line →"

    note=""
    [[ "$before" == "true" ]] && note+=" (continued from the previous day)"
    [[ "$after"  == "true" ]] && note+=" (continues into the next day)"

    lines+=("$line")
    echo "$key: $annotation$note"
done <<< "$per_key"

if [[ ${#lines[@]} -eq 0 ]]; then
    echo "No intervals recorded on $day - the Work block will be empty" >&2
fi

"$BLOCK" replace $block_opts ${lines[@]+"${lines[@]}"}

$owns_copy && "$BLOCK" diff --date "$day" --work-file "$work_file"

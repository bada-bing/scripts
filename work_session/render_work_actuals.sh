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
            start: .start,
            seconds: (((.end // (now | strftime("%Y%m%dT%H%M%SZ"))) | stamp) - (.start | stamp))
        })
        | group_by(.key)
        | map({
              key:      .[0].key,
              sessions: length,
              seconds:  (map(.seconds) | add),
              start:    (map(.start) | min)
          })
        | sort_by(.start)
        | .[] | [(.key // "-"), .sessions, .seconds] | @tsv
    '
)

# Built as whole lines, since the block is replaced rather than patched.
lines=()
while IFS=$'\t' read -r key sessions seconds; do
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
    lines+=("[[$page]] $annotation")
    echo "$key: $annotation"
done <<< "$per_key"

if [[ ${#lines[@]} -eq 0 ]]; then
    echo "No intervals recorded on $day - the Work block will be empty" >&2
fi

"$BLOCK" replace $block_opts ${lines[@]+"${lines[@]}"}

$owns_copy && "$BLOCK" diff --date "$day" --work-file "$work_file"

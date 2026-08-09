#!/usr/bin/env bash
#
# Renders a day's "# Work" annotations from Timewarrior: the number of sessions
# and the time they add up to, e.g. "2S (3h)".
#
# One-way, like the journal's "# Health" block. Every run reads Timewarrior and
# rewrites every entry, so correcting an interval by hand - or deleting one -
# is reflected the next time this runs. An entry left with no intervals loses
# its annotation rather than keeping a figure nothing supports any more.
#
# The journal says what was planned; this is the half that says what happened.
# Nothing here writes markers - that belongs to focus.sh.
#
# Usage: render_work_actuals.sh [YYYY-MM-DD] [--dry-run]

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

# Annotating several tasks means several edits, so they are applied to one
# working copy and diffed together. A caller mid-sequence passes its own copy
# and diffs when its whole change is assembled.
block_opts=""
if [[ -n "$work_file" ]]; then
    block_opts="--work-file $work_file"
elif $dry_run; then
    work_file=$(mktemp -u "${TMPDIR:-/tmp}/render-actuals.XXXXXX")
    block_opts="--work-file $work_file"
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
            seconds: (((.end // (now | strftime("%Y%m%dT%H%M%SZ"))) | stamp) - (.start | stamp))
        })
        | group_by(.key)
        | map({ key: .[0].key, sessions: length, seconds: (map(.seconds) | add) })
        | .[] | [(.key // "-"), .sessions, .seconds] | @tsv
    '
)

# A day with no intervals is not an early exit: its entries still have to lose
# any annotation they carry, which is the whole point of rendering from the
# store rather than adding to what is already written.
[[ -z "$per_key" ]] && echo "No intervals recorded on $day" >&2

# What Timewarrior says, as key -> annotation. This is the whole truth for the
# day: anything absent from it has no time recorded against it.
actuals=$(mktemp) || exit 1
seen=$(mktemp) || exit 1
trap 'rm -f "$actuals" "$seen"; $owns_copy && rm -f "$work_file"' EXIT

while IFS=$'\t' read -r key sessions seconds; do
    [[ -z "$key" ]] && continue

    # Intervals tagged with nothing task-shaped cannot be placed in the journal.
    # Reported rather than dropped, so a missing annotation is never a mystery.
    if [[ "$key" == "-" ]]; then
        echo "Skipped $sessions interval(s) on $day carrying no task key" >&2
        continue
    fi

    printf '%s\t%sS (%s)\n' "$key" "$sessions" "$(format_duration "$seconds")" >> "$actuals"
done <<< "$per_key"

# Every entry naming a task is rewritten from that truth, so one whose intervals
# were deleted loses its annotation instead of keeping a figure nothing supports.
while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    annotation=$(awk -F'\t' -v k="$key" '$1 == k { print $2; exit }' "$actuals")
    "$BLOCK" annotate "$key" "$annotation" --date "$day" $block_opts
    printf '%s\n' "$key" >> "$seen"
    if [[ -n "$annotation" ]]; then
        echo "$key: $annotation"
    else
        echo "$key: no time recorded"
    fi
done < <("$BLOCK" list --date "$day" $block_opts | awk -F'\t' '$2 != "" { print $2 }')

# Time logged for something the day never planned means focus was bypassed.
# Record it unmarked - it happened, it just was not planned - rather than
# letting the record quietly omit real work.
while IFS=$'\t' read -r key annotation; do
    [[ -z "$key" ]] && continue
    grep -qx "$key" "$seen" 2>/dev/null && continue
    "$BLOCK" set-marker "$key" - --date "$day" $block_opts
    "$BLOCK" annotate "$key" "$annotation" --date "$day" $block_opts
    echo "$key: $annotation (unplanned)"
done < "$actuals"

$owns_copy && "$BLOCK" diff --date "$day" $block_opts

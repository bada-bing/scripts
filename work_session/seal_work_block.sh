#!/usr/bin/env bash
#
# Seals a past day's "# Work" block: what was a live queue becomes a record.
#
# Markers are stripped, so the day reads as what happened rather than what was
# planned. An entry still queued - LATER, or a NOW left running - moves into
# today, and one that was never worked on leaves nothing behind, because
# planned-but-untouched is noise in a record.
#
# The day's actuals are rendered first, so an entry keeps the sessions and the
# time it earned before its marker goes.
#
# Idempotent: a sealed day has no markers left, so a second run does nothing.
#
# Usage: seal_work_block.sh [YYYY-MM-DD] [--dry-run]   (defaults to yesterday)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BLOCK="$SCRIPT_DIR/journal_work_block.sh"

day=""
dry_run=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        *)         day="$1"; shift ;;
    esac
done

today=$(date '+%Y-%m-%d')
day="${day:-$(date -j -v-1d '+%Y-%m-%d')}"

if [[ ! "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Usage: $(basename "$0") [YYYY-MM-DD] [--dry-run]" >&2
    exit 1
fi
if [[ "$day" == "$today" ]]; then
    echo "Error: today is still a live queue - only a past day can be sealed" >&2
    exit 1
fi

# A dry run threads a working copy per journal, since the seal writes to two:
# the day being sealed and today, which receives what carries over.
sealed_opts=""
today_opts=""
if $dry_run; then
    sealed_work=$(mktemp -u "${TMPDIR:-/tmp}/seal-day.XXXXXX")
    today_work=$(mktemp -u "${TMPDIR:-/tmp}/seal-today.XXXXXX")
    sealed_opts="--work-file $sealed_work"
    today_opts="--work-file $today_work"
    trap 'rm -f "$sealed_work" "$today_work"' EXIT
fi

# Time earned is recorded before anything is stripped, so the record is complete
# even for a day that was never closed with focus stop.
"$SCRIPT_DIR/render_work_actuals.sh" "$day" $sealed_opts >/dev/null

# Read the block once: the loop below rewrites it, and re-reading mid-flight
# would walk a file that is no longer the one enumerated.
entries=$("$BLOCK" list --date "$day" $sealed_opts)
[[ -z "$entries" ]] && exit 0

# Fields are read with awk rather than `read -r a b c`: tab is IFS whitespace, so
# read collapses the empty annotation field and shifts everything after it.
while IFS= read -r line; do
    marker=$(awk -F'\t' '{ print $1 }' <<< "$line")
    key=$(awk -F'\t' '{ print $2 }' <<< "$line")
    annot=$(awk -F'\t' '{ print $3 }' <<< "$line")
    text=$(awk -F'\t' '{ print $4 }' <<< "$line")
    [[ -z "$marker" ]] && continue

    # A DONE entry has finished with the day; only something still queued moves.
    [[ "$marker" == "DONE" ]] && continue

    # An entry with a [[page]] is carried by key, so today's copy gets the page
    # name resolved fresh. One without is carried by copying its text verbatim,
    # since there is nothing to look it up by.
    label="${key:-$text}"
    if [[ -n "$key" ]]; then
        already=$("$BLOCK" list --date "$today" $today_opts | awk -F'\t' -v k="$key" '$2 == k { print 1; exit }')
        [[ -z "$already" ]] && "$BLOCK" set-marker "$key" LATER --date "$today" $today_opts
    else
        already=$("$BLOCK" list --date "$today" $today_opts | awk -F'\t' -v t="$text" '$4 == t { print 1; exit }')
        [[ -z "$already" ]] && "$BLOCK" add "LATER $text" --date "$today" $today_opts
    fi

    # Time earned makes the entry part of the day's record, so it stays as well
    # as carrying. Without it there is nothing to record, and a planned-but-
    # untouched entry left behind is noise.
    if [[ -n "$annot" ]]; then
        echo "$label: carried to $today, kept on $day ($annot)"
    else
        "$BLOCK" remove "${key:-$text}" --date "$day" $sealed_opts
        echo "$label: carried to $today, dropped from $day"
    fi
done <<< "$entries"

# The queue becomes a record: no entry keeps a state, plain ones included.
"$BLOCK" strip-markers --date "$day" $sealed_opts

if $dry_run; then
    "$BLOCK" diff --date "$day" $sealed_opts
    "$BLOCK" diff --date "$today" $today_opts
fi

#!/usr/bin/env bash
#
# Rounds a day's intervals to the nearest quarter, once, at the close-up, so the
# day's record reads in round numbers. Until then work records exact times.
#
# Usage: round_work.sh [<YYYY-MM-DD>] [--dry-run]
#
# The intervals stay in order and never overlap: a start that rounds to before
# the previous end moves to that end. An interval that rounds to nothing keeps
# a quarter, the least the record says about work that happened. The interval
# still running is left alone, and the one before it ends no later than it
# starts.
#
# Timewarrior refuses an overlap at every step, so every edge that moves inward
# moves first and every edge that moves outward after: the targets never
# overlap, so neither pass meets an interval in its way.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

day=""
dry_run=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=true ;;
        -*) echo "Error: unknown option $arg" >&2; exit 1 ;;
        *)  day="$arg" ;;
    esac
done
day="${day:-$(date '+%Y-%m-%d')}"
if [[ ! "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Error: the day must be YYYY-MM-DD, got '$day'" >&2
    exit 1
fi
next_day=$(date -j -v+1d -f '%Y-%m-%d' "$day" '+%Y-%m-%d')

# One line per interval that moves: id, label, old start, old end, new start,
# new end, all in epoch seconds.
plan=$(timew export "$day" - "$next_day" 2>/dev/null | jq -r --argjson now "$(date '+%s')" '
    def stamp: strptime("%Y%m%dT%H%M%SZ") | mktime;
    def near: ((. + 450) / 900 | floor) * 900;
    def what: .annotation // ([.tags[]? | select(startswith("%"))] | first | if . then .[1:] else "an interval with no identity" end);
    (map(select(.end == null)) | first | if . then (.start | stamp) else null end) as $open
  | map(select(.end != null)) | sort_by(.start)
  | reduce .[] as $i ({prev: null, out: []};
        ($i.start | stamp) as $s0 | ($i.end | stamp) as $e0
      | ($s0 | near) as $sn
      | (if .prev != null and $sn < .prev then .prev else $sn end) as $s
      | ($e0 | near) as $en
      | (if $en <= $s then $s + 900 else $en end) as $e1
      | (if $open != null and $e1 > $open then $open else $e1 end) as $e
      | if $e <= $s then .prev = $e0
        else .out += [[$i.id, ($i | what), $s0, $e0, $s, $e]] | .prev = $e end)
  | .out[] | select(.[2] != .[4] or .[3] != .[5]) | @tsv') || exit 1

if [[ -z "$plan" ]]; then
    echo "$day: every interval is already on the quarter"
    exit 0
fi

clock() { date -r "$1" '+%H:%M'; }
stamp() { date -r "$1" '+%Y-%m-%dT%H:%M:%S'; }

while IFS=$'\t' read -r id label s0 e0 s e; do
    printf '%s  %s–%s  →  %s–%s\n' "$label" "$(clock "$s0")" "$(clock "$e0")" "$(clock "$s")" "$(clock "$e")"
done <<< "$plan"
$dry_run && exit 0

# Inward first: a start moving later, an end moving earlier. Then outward.
for pass in inward outward; do
    while IFS=$'\t' read -r id label s0 e0 s e; do
        if [[ "$pass" == inward ]]; then
            if [[ "$s" -gt "$s0" ]]; then timew modify start "@$id" "$(stamp "$s")" :yes >/dev/null || exit 1; fi
            if [[ "$e" -lt "$e0" ]]; then timew modify end "@$id" "$(stamp "$e")" :yes >/dev/null || exit 1; fi
        else
            if [[ "$s" -lt "$s0" ]]; then timew modify start "@$id" "$(stamp "$s")" :yes >/dev/null || exit 1; fi
            if [[ "$e" -gt "$e0" ]]; then timew modify end "@$id" "$(stamp "$e")" :yes >/dev/null || exit 1; fi
        fi
    done <<< "$plan"
done

"$SCRIPT_DIR/render_work_actuals.sh" "$day" >/dev/null

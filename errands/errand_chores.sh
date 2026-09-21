#!/usr/bin/env bash
#
# Reads the chore definitions - the SOA/Chores page. Read-only, and the only
# reader of it: a chore is a definition, written and changed by hand, and read
# when one is instantiated. Nothing here writes to the page.
#
# A chore is a class and an errand is an instance, so the page holds classes and
# nothing on it is ever started, marked or completed.
#
# A chore is a top-level block carrying one property, its frequency:
#
#   - Triage the Slack activity feed
#     frequency:: daily
#   - Review the week
#     frequency:: weekly friday
#   - Pay the rent
#     frequency:: monthly 3rd
#   - Drain the old backlog page
#     frequency:: on-demand
#
# The frequency is a property rather than part of the label because the label is
# the identity: it groups two sittings of one chore into one entry in the record,
# so writing "(daily)" into it would carry that into the record and split the
# history in two the day the frequency changed.
#
# Usage:
#   errand_chores.sh list          every chore, as label and frequency
#   errand_chores.sh due [DATE]    the labels due on DATE, today by default
#
# Whether a chore is due is a pure function of the date and the frequency.
# Nothing is stored about when it last ran or when it runs next - for a calendar
# rule that would only cache what the rule already says, and a cache can drift
# out of step with it.
#
# A rule fires on its date whatever day of the week that is: working days are a
# job concept, and chores are not only job work. A missed cycle is skipped rather
# than owed, since the work is done against the world as it is now.
#
# monthly <n> falls on the last day of a month too short for it, so a chore on
# the 31st is not silently skipped in February.
#
# A chore with no frequency, or one that cannot be read, is reported and skipped.
# The page is configuration, and a line that says nothing is a mistake to see.

set -uo pipefail

LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# Logseq stores a namespaced page with the slash percent-encoded, so the name
# written in the graph and the name on disk are not the same string.
PAGE="SOA/Chores"
file="$LOGSEQ_GRAPH_PATH/pages/${PAGE//\//%2F}.md"

DAYS="monday tuesday wednesday thursday friday saturday sunday"

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
}

verb="${1:-}"
shift || true

case "$verb" in
    -h|--help) usage; exit 0 ;;
    "")        usage >&2; exit 1 ;;
esac

if [[ ! -f "$file" ]]; then
    echo "Error: no such page: $file" >&2
    exit 1
fi

# label, then frequency. A property sits on the line under the block it belongs
# to, indented to the block's text, which is how Logseq writes one.
chores() {
    awk '
        function flush() {
            if (label == "") return
            if (freq == "")
                printf "Warning: no frequency, skipped: %s\n", label > "/dev/stderr"
            else
                print label "\t" freq
            label = ""; freq = ""
        }
        NR == 1 && /^---$/ { fm = 1; next }
        fm                 { if (/^---$/) fm = 0; next }
        /^- / {
            flush()
            label = substr($0, 3)
            sub(/[[:space:]]+$/, "", label)
            next
        }
        /^[[:space:]]+frequency::[[:space:]]*/ {
            freq = $0
            sub(/^[[:space:]]+frequency::[[:space:]]*/, "", freq)
            sub(/[[:space:]]+$/, "", freq)
            next
        }
        END { flush() }
    ' "$file"
}

# The last day of the month DATE falls in: to its first, on a month, back a day.
last_day_of_month() {
    date -j -v1d -v+1m -v-1d -f '%Y-%m-%d' "$1" '+%-d'
}

# 0 due, 1 not due, 2 the frequency cannot be read.
is_due() {
    local freq="$1" day="$2" kind arg
    read -r kind arg <<< "$freq"

    case "$kind" in
        daily)     return 0 ;;
        on-demand) return 1 ;;

        weekly)
            local want today_name match="" d
            want=$(printf '%s' "$arg" | tr 'A-Z' 'a-z')
            # Three letters are enough to name a day, and fewer are not: "s"
            # would answer to both Saturday and Sunday.
            [[ ${#want} -ge 3 ]] || return 2
            for d in $DAYS; do
                [[ "$d" == "$want"* ]] && match="$d"
            done
            [[ -n "$match" ]] || return 2
            today_name=$(date -j -f '%Y-%m-%d' "$day" '+%A' | tr 'A-Z' 'a-z')
            [[ "$today_name" == "$match" ]]
            ;;

        monthly)
            local n dom last
            n="${arg%%[!0-9]*}"          # an ordinal is written as it is read: 3rd
            [[ -n "$n" ]] || return 2
            n=$((10#$n))
            (( n >= 1 && n <= 31 )) || return 2
            last=$(last_day_of_month "$day")
            (( n > last )) && n=$last
            dom=$(date -j -f '%Y-%m-%d' "$day" '+%-d')
            (( dom == n ))
            ;;

        *) return 2 ;;
    esac
}

case "$verb" in
    list)
        chores
        ;;

    due)
        day="${1:-$(date '+%Y-%m-%d')}"
        if [[ ! "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            echo "Error: the date must be YYYY-MM-DD, got '$day'" >&2
            exit 1
        fi

        while IFS=$'\t' read -r label freq; do
            is_due "$freq" "$day"
            case $? in
                0) printf '%s\n' "$label" ;;
                1) ;;
                *) printf 'Warning: cannot read the frequency "%s" of: %s\n' \
                       "$freq" "$label" >&2 ;;
            esac
        done < <(chores)
        ;;

    *)
        echo "Error: unknown verb '$verb'" >&2
        usage >&2
        exit 1
        ;;
esac

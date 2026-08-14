#!/usr/bin/env bash
#
# Picks what to work on: something named in today's plan, a pending task, or a
# repository with no task attached. All of them live in one list, because
# narrowing to the wrong kind first is how you miss the thing you wanted.
#
# The plan comes first, in the order it was written - that order is a decision,
# while urgency is a computation for everything not decided about. Then the tasks
# the plan does not name, by urgency, then the repositories.
#
# An entry containing a "[[page]]" link names a page, and only a page with a
# pending task can be started. Anything else is prose, and prose is a label for
# work with no task. One rule for every link is easier to hold than a second one
# about which links look like task keys.
#
# An entry naming a page with no pending task is shown dimmed rather than hidden,
# since a plan pointing at work Taskwarrior knows nothing about is worth seeing,
# and picking it explains itself.
#
# A marker written by hand is shown back - "planned later", "planned now" - but
# only shown: it does not order the list and it cannot refuse a start. The three
# words the journal reader recognises are LATER, NOW and DONE; anything else stays
# part of the entry's text.
#
# Prints the selection as two tab-separated fields - "task <key>", "adhoc <label>",
# "unstartable <key>" or "repo <path>" - and nothing when the picker is dismissed.
#
# Usage: select_work.sh [--tasks]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# Basic ANSI only, so the terminal's own theme decides the shades.
DIM=$'\033[2m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

# --tasks drops the repositories: a repository is a place rather than work, so
# offering one where work is wanted is only a way to pick wrong.
tasks_only=false
[[ "${1:-}" == "--tasks" ]] && tasks_only=true

pending_tasks=$(task status:pending export 2>/dev/null)

# The project and page belong to the task, so they are looked up the same way
# wherever a row is built.
project_of() {
    printf '%s' "$pending_tasks" | jq -r --arg k "$1" \
        'map(select(.description == $k)) | .[0].project // "-"'
}

title_of() {
    local page
    page=$(basename "$(ls "$LOGSEQ_GRAPH_PATH/pages/$1"-*.md 2>/dev/null | head -1)" .md 2>/dev/null)
    printf '%s' "${page#"$1"-}"
}

is_pending() {
    printf '%s' "$pending_tasks" | jq -e --arg k "$1" \
        'any(.[]; .description == $k)' >/dev/null 2>&1
}

# rank kind answer, then the display columns.
#
# Every colour is applied to an already-padded cell, never inside a padded field:
# printf counts an escape sequence toward the field's width, which would shift that
# row left of every other one.
#
# The planned column is coloured because planned rows sort to the top only until a
# query is typed - fzf then reorders the list, and colour is what survives that.
row() {
    local rank="$1" kind="$2" answer="$3"; shift 3
    local kind_col="$1" planned_col="$2"; shift 2

    local cell
    cell=$(printf '%-14s' "$planned_col")
    # A dimmed row is already saying the louder thing, so it keeps its own shade.
    if [[ "$kind" != "unstartable" ]]; then
        case "$planned_col" in
            "planned now")  cell="$YELLOW$cell$RESET" ;;
            "planned done") cell="$DIM$cell$RESET" ;;
            planned*)       cell="$GREEN$cell$RESET" ;;
        esac
    fi

    local display
    display=$(printf '%-8s %s %-30s %-6s %s' "$kind_col" "$cell" "$@")
    # A row with no project or title would otherwise trail the padding of both.
    display="${display%"${display##*[![:space:]]}"}"
    [[ "$kind" == "unstartable" ]] && display="$DIM$display$RESET"
    printf '%s\t%s\t%s\t%s\n' "$rank" "$kind" "$answer" "$display"
}

# Everything named in today's plan, in the order it was written. An entry carrying
# a "[[page]]" link is a task reference; anything else is prose, and prose is a
# label for work with no task.
#
# list separates its fields with tabs, and bash treats a tab as whitespace in IFS -
# leading ones are stripped and runs of them collapse, so an entry with an empty
# field would arrive shifted a column to the left. A unit separator does not
# collapse, which is why the fields are handed over on one.
planned() {
    "$SCRIPT_DIR/journal_work_block.sh" list 2>/dev/null \
        | awk -F'\t' 'BEGIN { OFS = "\x1f" } { print $1, $2, $4 }' \
        | while IFS=$'\x1f' read -r marker key text; do
            [[ -z "$text" ]] && continue
            local shown="planned${marker:+ $(printf '%s' "$marker" | tr '[:upper:]' '[:lower:]')}"

            if [[ "$text" != *"[["*"]]"* ]]; then
                row 0 adhoc "$text" "adhoc" "$shown" "$text" "" ""
            elif [[ -n "$key" ]] && is_pending "$key"; then
                row 0 task "$key" "task" "$shown" "$key" "$(project_of "$key")" "$(title_of "$key")"
            else
                # Dimmed, not hidden: the plan points at a page with no task.
                row 0 unstartable "${key:-$text}" \
                    "no task" "$shown" "${key:-$text}" "-" \
                    "$([[ -n "$key" ]] && title_of "$key")"
            fi
        done
}

# The pending tasks the plan does not name, by urgency.
unplanned() {
    local planned_keys
    planned_keys=$(mktemp) || return 1
    "$SCRIPT_DIR/journal_work_block.sh" list 2>/dev/null \
        | awk -F'\t' '$2 != "" { print $2 }' > "$planned_keys"

    printf '%s' "$pending_tasks" \
        | jq -r 'sort_by(-.urgency) | .[] | [.description, (.project // "-")] | @tsv' \
        | while IFS=$'\t' read -r key project; do
            grep -qxF "$key" "$planned_keys" 2>/dev/null && continue
            row 1 task "$key" "task" "-" "$key" "$project" "$(title_of "$key")"
        done
    rm -f "$planned_keys"
}

repos() {
    local roots
    IFS=':' read -ra roots <<< "${SRC_PATH:-$HOME/Developer/src}"
    find "${roots[@]}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort \
        | while read -r path; do
            row 2 repo "$path" "repo" "-" "$(basename "$path")" "" "$path"
        done
}

# Four tab-separated fields: rank, kind, what to return, and the line to show.
# fzf displays only the fourth and hands the whole line back, so the answer is
# read from a field of its own rather than parsed out of the formatting. Display
# columns can then hold anything - spaces, escape codes - without breaking the
# result. -s keeps each group's own order within its rank.
selection=$(
    { planned; unplanned; $tasks_only || repos; } \
        | sort -s -k1,1n \
        | fzf --ansi --height=60% --reverse --delimiter='\t' --with-nth=4 \
              --prompt="$($tasks_only && echo 'work> ' || echo 'go> ')"
)

[[ -z "$selection" ]] && exit 0

kind=$(awk -F'\t' '{print $2}' <<< "$selection")
answer=$(awk -F'\t' '{print $3}' <<< "$selection")
case "$kind" in
    task|adhoc|repo|unstartable) printf '%s\t%s\n' "$kind" "$answer" ;;
    *)                           exit 1 ;;
esac

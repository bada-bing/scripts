#!/usr/bin/env bash
#
# Picks what to work on: an errand from today's journal, a pending task, or a
# repository with no task attached. All of them live in one list, because
# narrowing to the wrong kind first is how you miss the thing you wanted.
#
# The day's errands come first, in the order they were written - that order is the
# prioritisation, while urgency is a computation for everything not decided about.
# Then every pending task by urgency, then the repositories.
#
# Nothing is filtered out against the journal. Tasks are not named there any more,
# so the two halves cannot offer the same thing twice: errands come from the
# block, tasks from Taskwarrior, which is the ground truth for what is pending.
#
# An entry whose text begins with "[[" is a task reference, shown dimmed and not
# startable - tasks are not managed in the block, whether or not the page behind
# the link has a pending task. A link further along the text leaves the entry an
# ordinary errand, so "set up [[CHARLIE_09]] next" is one.
#
# A completed errand is dropped rather than shown, so DONE is what takes an errand
# out of the picker. No marker is displayed: LATER and NOW are no longer written,
# and the ones left in older journals are inert.
#
# Prints the selection as two tab-separated fields - "task <key>", "adhoc <label>",
# "unstartable <key>" or "repo <path>" - and nothing when the picker is dismissed.
# The row says "errand" where the field says "adhoc": the first is the word the
# system uses, the second is what get_active_identity.sh prints for the same work.
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

# The page belongs to the task, so it is looked up the same way wherever a row
# is built.
title_of() {
    local page
    page=$(basename "$(ls "$LOGSEQ_GRAPH_PATH/pages/$1"-*.md 2>/dev/null | head -1)" .md 2>/dev/null)
    printf '%s' "${page#"$1"-}"
}

# rank kind answer, then the display columns.
#
# Every colour is applied to an already-padded cell, never inside a padded field:
# printf counts an escape sequence toward the field's width, which would shift that
# row left of every other one.
#
# Only Errand and Task are told apart, and on the kind cell, because rows sort into
# their groups only until a query is typed - fzf then reorders the list, and colour
# is what survives that. A dimmed row is already saying the louder thing, so it
# keeps its own shade.
row() {
    local rank="$1" kind="$2" answer="$3"; shift 3
    local kind_col="$1"; shift

    local cell
    cell=$(printf '%-8s' "$kind_col")
    case "$kind" in
        adhoc) cell="$YELLOW$cell$RESET" ;;
        task)  cell="$GREEN$cell$RESET" ;;
    esac

    local display
    display=$(printf '%s %-30s %-6s %s' "$cell" "$@")
    # A row with no project or title would otherwise trail the padding of both.
    display="${display%"${display##*[![:space:]]}"}"
    [[ "$kind" == "unstartable" ]] && display="$DIM$display$RESET"
    printf '%s\t%s\t%s\t%s\n' "$rank" "$kind" "$answer" "$display"
}

# The day's errands, in the order they were written.
#
# list separates its fields with tabs, and bash treats a tab as whitespace in IFS -
# leading ones are stripped and runs of them collapse, so an entry with an empty
# field would arrive shifted a column to the left. A unit separator does not
# collapse, which is why the fields are handed over on one.
errands() {
    "$SCRIPT_DIR/journal_work_block.sh" list 2>/dev/null \
        | awk -F'\t' 'BEGIN { OFS = "\x1f" } { print $1, $2, $4 }' \
        | while IFS=$'\x1f' read -r marker key text; do
            [[ -z "$text" ]] && continue
            # Completing an errand is what takes it out of the picker, so a done
            # one is dropped rather than shown in a shade meaning nothing.
            [[ "$marker" == "DONE" ]] && continue

            if [[ "$text" == "[["* ]]; then
                # Dimmed, not hidden: a task reference in the block is worth
                # seeing, and picking it explains itself.
                row 0 unstartable "${key:-$text}" \
                    "task ref" "${key:-$text}" "-" \
                    "$([[ -n "$key" ]] && title_of "$key")"
            else
                row 0 adhoc "$text" "errand" "$text" "" ""
            fi
        done
}

# Every pending task, by urgency.
tasks() {
    printf '%s' "$pending_tasks" \
        | jq -r 'sort_by(-.urgency) | .[] | [.description, (.project // "-")] | @tsv' \
        | while IFS=$'\t' read -r key project; do
            row 1 task "$key" "task" "$key" "$project" "$(title_of "$key")"
        done
}

repos() {
    local roots
    IFS=':' read -ra roots <<< "${SRC_PATH:-$HOME/Developer/src}"
    find "${roots[@]}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort \
        | while read -r path; do
            row 2 repo "$path" "repo" "$(basename "$path")" "" "$path"
        done
}

# Four tab-separated fields: rank, kind, what to return, and the line to show.
# fzf displays only the fourth and hands the whole line back, so the answer is
# read from a field of its own rather than parsed out of the formatting. Display
# columns can then hold anything - spaces, escape codes - without breaking the
# result. -s keeps each group's own order within its rank.
selection=$(
    { errands; tasks; $tasks_only || repos; } \
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

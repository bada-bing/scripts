#!/usr/bin/env bash
#
# Adds an item at the end of today's # Plan: a task by its key, or an errand by
# its text.
#
# Usage: plan_work.sh <task-key | "errand text"> [--planned <duration>] [--dry-run]
#
# A task is written as a link to its page, carrying the time planned for it as
# planned::. --planned sets it, written as the journal writes durations (1h30m).
# Without it, it is taken from the task's priority, a heuristic: H 2h, M 1h, L or
# none 30m.
# A later change of priority does not rewrite a past day's plan, so planned
# against worked stays readable over many days.
#
# An errand is handed to errand capture, which is the only writer of errands.
#
# The argument dispatches by resolution, as work start does: a pending task means
# a task, and anything else is an errand's text. A key-shaped argument with no
# pending task is an error, so a typo cannot quietly become an errand.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JOURNAL="$SCRIPT_DIR/journal_work_block.sh"
ERRAND="$SCRIPT_DIR/../errands/errand.sh"

what=""
planned=""
opts=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) opts+=(--dry-run) ;;
        --planned) planned="${2:-}"; shift ;;
        -*)
            echo "Error: unknown option '$1'" >&2
            exit 1
            ;;
        *)
            if [[ -n "$what" ]]; then
                echo "Error: plan takes one item; quote the text" >&2
                exit 1
            fi
            what="$1"
            ;;
    esac
    shift
done

if [[ -z "$what" ]]; then
    echo "Usage: work plan <task-key | \"errand text\">" >&2
    exit 1
fi

task_json=$(task status:pending export 2>/dev/null \
    | jq -c --arg key "$what" 'map(select(.description == $key)) | .[0] // empty')

if [[ -z "$task_json" ]]; then
    if [[ "$what" == "[["* ]]; then
        echo "Error: a task is planned by its key" >&2
        echo "  work plan <task-key>" >&2
        exit 1
    fi
    if [[ "$what" =~ ^[A-Za-z0-9]+[-_.][A-Za-z0-9]*[0-9]+$ ]]; then
        printf 'Error: %s has no pending task\n' "$what" >&2
        echo "  check the key" >&2
        exit 1
    fi
    if [[ -n "$planned" ]]; then
        echo "Error: an errand takes no planned time" >&2
        exit 1
    fi
    exec "$ERRAND" capture "$what" ${opts[@]+"${opts[@]}"}
fi

key="$what"

# A task is in the plan once. A second entry would split its planned time.
if "$JOURNAL" list 2>/dev/null | awk -F'\t' -v k="$key" '$2 == k { found = 1 } END { exit !found }'; then
    printf 'Error: %s is already in the plan\n' "$key" >&2
    exit 1
fi

page=$("$SCRIPT_DIR/find_task_page.sh" "$key") || exit 1

if [[ -n "$planned" ]]; then
    if [[ ! "$planned" =~ ^([0-9]+h)?([0-9]+m)?$ || "$planned" == "" ]]; then
        printf "Error: '%s' is not a duration like 1h30m\n" "$planned" >&2
        exit 1
    fi
else
    case "$(jq -r '.priority // ""' <<< "$task_json")" in
        H) planned="2h" ;;
        M) planned="1h" ;;
        *) planned="30m" ;;
    esac
fi

printf -- '- [[%s]]\n  planned:: %s\n' "$(basename "$page" .md)" "$planned" \
    | "$JOURNAL" add ${opts[@]+"${opts[@]}"} || exit 1

[[ ${#opts[@]} -eq 0 ]] && printf 'planned: %s for %s\n' "$key" "$planned"
exit 0

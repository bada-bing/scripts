#!/usr/bin/env bash
#
# work - the command-line front door to record_work.sh.
#
# With no verb it reports the open interval, which is the question asked most
# often. Starting is always said explicitly, so it reads as the opposite of
# stopping and cannot happen by mistyping something else.
#
# Selection lives here rather than in record_work.sh, which takes a key and
# never asks a question.
#
# Usage:
#   work.sh                              report the open interval and the day
#   work.sh start [<what>] [<time>]      pick when nothing is given
#   work.sh start "<label>"              work with no task, labelled in words
#   work.sh log <what> <time> <duration> [--date D]  record finished work
#   work.sh plan <task-key | "<errand>">  add it at the end of today's plan
#   work.sh done                         stop, then mark the item done for today
#   work.sh stop                         close the interval at its exact time,
#                                        render the day
#   work.sh round [<day>]                round the day's intervals to the quarter
#   work.sh render [<day>]               render a day's record again

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<'USAGE'
Usage:
  work                        what is being recorded right now, the time worked
                              today and what comes next
  work start                  pick something, then start recording it
  work start <task-key>       start that one, skipping the picker
  work start <what> 16:00     start it, backdated to that time
  work start "<label>"        record work that has no task, under that label
  work log <what> 16:00 2h    record work already finished, opening nothing
  work log <what> 9:06 1h40m --date 2026-09-19   write up another day
  work plan <task-key>        add the task at the end of today's plan
  work plan "<errand>"        add the errand there, through errand capture
  work done                   stop as work stop does, then mark the item done
                              for today
  work stop                   offer to close the task's discussion, then close
                              the interval at its exact time
  work round [<day>]          round the day's intervals to the nearest quarter,
                              once, at the close-up
  work render [<day>]         render a day's record again from Timewarrior

--dry-run works throughout: it applies nothing and prints what it would do.
A verb is handed to record_work.sh unchanged.
USAGE
}

# Offers to close the discussion of the task being recorded, when the topic
# overview has one open, which merges its branch into the knowledge base's
# main. Only that one: another discussion belongs to work this interval does
# not record. A close that fails, on a conflict for instance, stops here with
# the interval still running: git is reconciled before the record is written,
# and the conflict is resolved in the terminal. Without the tool, or with no
# discussion of the task open, nothing is asked.
close_discussion() {
    local dry_run="$1" key="$2" dir="${TOPIC_OVERVIEW_DIR:-$HOME/Developer/src/topic_overview}" answer
    [[ -n "$key" && -f "$dir/package.json" ]] || return 0
    pnpm --dir "$dir" --silent topic list 2>/dev/null | awk '{print $1}' | grep -qxF -- "$key" || return 0
    if ! read -r -p "Close the discussion of $key, merging it into main? [Y/n] " answer; then
        echo; echo "No answer; the interval is still running" >&2
        return 1
    fi
    case "$answer" in
        ""|y|Y)
            if $dry_run; then
                printf 'would: topic close %s\n' "$key" >&2
            elif ! pnpm --dir "$dir" --silent topic close "$key"; then
                printf '  resolve it, then stop again; the interval is still running\n' >&2
                return 1
            fi ;;
        *) ;;
    esac
}

# Closes the open interval at its exact times, asking first whether the task's
# discussion closes. The close-up rounds the day once, with work round.
stop_interval() {
    local dry_run=false arg kind label
    for arg in "$@"; do
        [[ "$arg" == --dry-run ]] && dry_run=true
    done
    if [[ "$(timew get dom.active 2>/dev/null || true)" == "1" ]]; then
        IFS=$'\t' read -r kind label <<< "$("$SCRIPT_DIR/get_active_identity.sh")"
        [[ "${kind:-}" == "task" ]] && { close_discussion "$dry_run" "$label" || return 1; }
    fi
    "$SCRIPT_DIR/record_work.sh" stop "$@"
}

verb="${1:-}"

case "$verb" in
    -h|--help)
        usage
        exit 0
        ;;

    render)
        shift
        exec "$SCRIPT_DIR/render_work_actuals.sh" "$@"
        ;;

    status)
        "$SCRIPT_DIR/record_work.sh" "$@"
        "$SCRIPT_DIR/report_day.sh"
        ;;

    plan)
        shift
        exec "$SCRIPT_DIR/plan_work.sh" "$@"
        ;;

    round)
        shift
        exec "$SCRIPT_DIR/round_work.sh" "$@"
        ;;

    # Stopping asks one thing: whether the task's discussion closes, since
    # closing reconciles the knowledge base's git and belongs before the
    # interval is recorded. The interval is recorded at its exact times, and
    # work round makes the day round once, at the close-up.
    stop)
        shift
        for arg in "$@"; do
            [[ "$arg" == --dry-run ]] || { echo "Error: unknown option $arg" >&2; exit 1; }
        done
        stop_interval "$@" || exit $?
        "$SCRIPT_DIR/report_day.sh"
        ;;

    # Done is stopping plus marking the item done for today. The item is looked
    # up before anything is stopped, so a refusal leaves the interval running and
    # the plan as it was. An errand is marked by errand complete, the only writer
    # of errands, which finds the interval already closed and touches no time.
    done)
        shift
        for arg in "$@"; do
            [[ "$arg" == --dry-run ]] || { echo "Error: unknown option $arg" >&2; exit 1; }
        done

        IFS=$'\t' read -r kind label <<< "$("$SCRIPT_DIR/get_active_identity.sh")"
        if [[ -z "${label:-}" ]]; then
            echo "Error: nothing is being recorded" >&2
            echo "  to mark an errand done without recording: errand complete '<text>'" >&2
            exit 1
        fi

        if ! "$SCRIPT_DIR/journal_work_block.sh" list \
             | awk -F'\t' -v k="$label" -v kind="$kind" \
                   '(kind == "task" ? $2 : $4) == k { found = 1 } END { exit !found }'; then
            printf "Error: %s is not in today's plan\n" "$label" >&2
            echo "  to stop without marking anything: work stop" >&2
            exit 1
        fi

        stop_interval "$@" || exit $?

        if [[ "$kind" == "task" ]]; then
            "$SCRIPT_DIR/journal_work_block.sh" mark "$label" "$@"
        else
            "$SCRIPT_DIR/../errands/errand.sh" complete "$label" "$@"
        fi || exit $?
        "$SCRIPT_DIR/report_day.sh"
        ;;

    # Nothing to pick for: log names work that is over, so there is no list of
    # candidates it could offer.
    log)
        exec "$SCRIPT_DIR/record_work.sh" "$@"
        ;;

    start)
        shift
        # An argument means there is nothing to ask, and the operation makes the same
        # check for itself. It also knows when the arguments record the past rather
        # than start anything, which nothing open has any business refusing.
        for arg in "$@"; do
            [[ "$arg" == -* ]] && continue
            exec "$SCRIPT_DIR/record_work.sh" start "$@"
        done

        # Decline before asking. Offering a list that cannot be acted on wastes the
        # choice and implies something can be started when nothing can.
        "$SCRIPT_DIR/refuse_if_recording.sh" || exit 1
        "$SCRIPT_DIR/refuse_if_unplanned.sh" || exit 1

        selection=$("$SCRIPT_DIR/select_work.sh" --tasks) || exit 1
        [[ -z "$selection" ]] && exit 0

        IFS=$'\t' read -r kind key <<< "$selection"
        [[ -z "$key" ]] && exit 0

        # The picker shows a link to a page with no pending task dimmed, so
        # honouring that here is what makes the row mean what it says.
        if [[ "$kind" == "unstartable" ]]; then
            printf 'Error: %s has no pending task\n' "$key" >&2
            echo "  bootstrap the task if you meant to work on it" >&2
            exit 1
        fi

        exec "$SCRIPT_DIR/record_work.sh" start "$key" "$@"
        ;;

    ""|-*)
        # Nothing but flags: report, rather than guess at an action.
        "$SCRIPT_DIR/record_work.sh" status "$@"
        "$SCRIPT_DIR/report_day.sh"
        ;;

    *)
        echo "Error: unknown verb '$verb'" >&2
        echo "  to start work on it: work start $verb" >&2
        exit 1
        ;;
esac

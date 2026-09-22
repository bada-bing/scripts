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
#   work.sh                              report the open interval
#   work.sh start [<what>] [<time>]      pick when nothing is given
#   work.sh start "<label>"              work with no task, labelled in words
#   work.sh log <what> <time> <duration> [--date D]  record finished work
#   work.sh stop                         close the interval, render the day
#   work.sh render [<day>]               render a day's record again

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<'USAGE'
Usage:
  work                        what is being recorded right now
  work start                  pick something, then start recording it
  work start <task-key>       start that one, skipping the picker
  work start <what> 16:00     start it, backdated to that time
  work start "<label>"        record work that has no task, under that label
  work log <what> 16:00 2h    record work already finished, opening nothing
  work log <what> 9:06 1h40m --date 2026-09-19   write up another day
  work stop                   close the interval and render the day
  work render [<day>]         render a day's record again from Timewarrior

--dry-run works throughout: it applies nothing and prints what it would do.
A verb is handed to record_work.sh unchanged.
USAGE
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

    stop|status)
        exec "$SCRIPT_DIR/record_work.sh" "$@"
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

        selection=$("$SCRIPT_DIR/select_work.sh" --tasks) || exit 1
        [[ -z "$selection" ]] && exit 0

        IFS=$'\t' read -r kind key <<< "$selection"
        [[ -z "$key" ]] && exit 0

        # The picker shows a task reference in the journal dimmed, so honouring
        # that here is what makes the row mean what it says. Starting the task is
        # still a keystroke away, and saying which one is the whole of the answer.
        if [[ "$kind" == "unstartable" ]]; then
            printf 'Error: %s is a task reference, not an errand\n' "$key" >&2
            printf '  tasks are not started from the day block: work start %s\n' "$key" >&2
            exit 1
        fi

        exec "$SCRIPT_DIR/record_work.sh" start "$key" "$@"
        ;;

    ""|-*)
        # Nothing but flags: report, rather than guess at an action.
        exec "$SCRIPT_DIR/record_work.sh" status "$@"
        ;;

    *)
        echo "Error: unknown verb '$verb'" >&2
        echo "  to start work on it: work start $verb" >&2
        exit 1
        ;;
esac

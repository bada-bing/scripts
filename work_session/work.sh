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
#   work.sh start [<what>] [<time>] [<duration>]   pick when nothing is given
#   work.sh start "<label>"              work with no task, labelled in words
#                                        a duration records the past, opening nothing
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
  work start <what> 16:00 2h  record work already done, opening nothing
  work start "<label>"        record work that has no task, under that label
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

        IFS=$'\t' read -r _ key <<< "$selection"
        [[ -z "$key" ]] && exit 0

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

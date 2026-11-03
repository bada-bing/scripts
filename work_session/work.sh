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
#   work.sh plan <task-key | "<errand>">  add it at the end of today's plan
#   work.sh done                         stop, then mark the item done for today
#   work.sh stop                         close the interval, rounded to the
#                                        quarter once confirmed, render the day
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
  work plan <task-key>        add the task at the end of today's plan
  work plan "<errand>"        add the errand there, through errand capture
  work done                   stop as work stop does, then mark the item done
                              for today
  work stop                   offer to close the task's discussion, then close
                              the interval, rounded to the quarter once confirmed
  work render [<day>]         render a day's record again from Timewarrior

--dry-run works throughout: it applies nothing and prints what it would do.
A verb is handed to record_work.sh unchanged.
USAGE
}

# The nearest quarter of an hour, in epoch seconds.
quarter() {
    printf '%d' $(( ($1 + 450) / 900 * 900 ))
}

clock() {
    date -r "$1" '+%H:%M'
}

# An edge as record_work.sh takes it, with its day, since the interval may
# have crossed midnight.
stamp() {
    date -r "$1" '+%Y-%m-%dT%H:%M'
}

# Minutes as the journal spells a duration: 2h, 2h30m, 45m.
spell() {
    local h=$(( $1 / 60 )) m=$(( $1 % 60 ))
    if   [[ "$h" -eq 0 ]]; then printf '%dm' "$m"
    elif [[ "$m" -eq 0 ]]; then printf '%dh' "$h"
    else printf '%dh%02dm' "$h" "$m"
    fi
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
        exec "$SCRIPT_DIR/record_work.sh" "$@"
        ;;

    plan)
        shift
        exec "$SCRIPT_DIR/plan_work.sh" "$@"
        ;;

    # Stopping is where the day's record gets its shape, so it is the one verb
    # that asks: first whether the task's discussion closes, since closing
    # reconciles the knowledge base's git and belongs before the interval is
    # recorded, then where the interval's edges go. Precise times are not the
    # point of the record, so the edges are proposed rounded to the nearest
    # quarter, and recorded only once confirmed. The operation itself still
    # takes the edges as arguments and asks nothing.
    stop)
        shift
        dry_run=false
        for arg in "$@"; do
            case "$arg" in
                --dry-run) dry_run=true ;;
                *) echo "Error: unknown option $arg" >&2; exit 1 ;;
            esac
        done
        [[ "$(timew get dom.active 2>/dev/null || true)" == "1" ]] \
            || exec "$SCRIPT_DIR/record_work.sh" stop "$@"

        IFS=$'\t' read -r kind label <<< "$("$SCRIPT_DIR/get_active_identity.sh")"
        [[ "${kind:-}" == "task" ]] && { close_discussion "$dry_run" "$label" || exit 1; }

        start_epoch=$(date -j -u -f '%Y%m%dT%H%M%SZ' \
            "$(timew get dom.active.json | jq -r .start)" '+%s') || exit 1
        now=$(date '+%s')
        from=$(quarter "$start_epoch")
        to=$(quarter "$now")
        # An interval shorter than a quarter rounds to nothing, and a quarter
        # is the least the record says about work that happened.
        [[ "$to" -gt "$from" ]] || to=$((from + 900))

        printf '%s  %s–%s  →  %s–%s (%s)\n' "${label:-an interval with no identity}" \
            "$(clock "$start_epoch")" "$(clock "$now")" \
            "$(clock "$from")" "$(clock "$to")" "$(spell $(( (to - from) / 60 )))"
        while :; do
            if ! read -r -p "Record $(clock "$from")–$(clock "$to")? [Y/n/<start> <end>] " answer; then
                echo; echo "No answer; the interval is still running" >&2
                exit 1
            fi
            # A refusal, exit 2, is an overlap with what is already recorded,
            # said with what is in the way; other times can then be given.
            case "$answer" in
                ""|y|Y)
                    "$SCRIPT_DIR/record_work.sh" stop --start "$(stamp "$from")" --end "$(stamp "$to")" "$@"
                    rc=$?; [[ "$rc" -eq 2 ]] && continue; exit "$rc" ;;
                n|N)
                    exec "$SCRIPT_DIR/record_work.sh" stop "$@" ;;
                *)
                    # Two times, each read on the day of the edge it replaces,
                    # so an interval that crossed midnight keeps its days.
                    read -r a b <<< "$answer"
                    if [[ "$a" =~ ^[0-9]{1,2}:[0-9]{2}$ && "$b" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
                        a=$(date -j -f '%Y-%m-%d %H:%M' "$(date -r "$from" '+%Y-%m-%d') $a" '+%s') || continue
                        b=$(date -j -f '%Y-%m-%d %H:%M' "$(date -r "$to" '+%Y-%m-%d') $b" '+%s') || continue
                        if [[ "$b" -le "$a" ]]; then
                            echo "  the end must come after the start" >&2
                            continue
                        fi
                        from=$a; to=$b
                        "$SCRIPT_DIR/record_work.sh" stop --start "$(stamp "$from")" --end "$(stamp "$to")" "$@"
                        rc=$?; [[ "$rc" -eq 2 ]] && continue; exit "$rc"
                    fi
                    echo "  Enter records the rounded times, n the exact ones, or give two times: 08:00 10:45" >&2 ;;
            esac
        done
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

        "$0" stop "$@" || exit $?

        if [[ "$kind" == "task" ]]; then
            "$SCRIPT_DIR/journal_work_block.sh" mark "$label" "$@"
        else
            "$SCRIPT_DIR/../errands/errand.sh" complete "$label" "$@"
        fi
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
        exec "$SCRIPT_DIR/record_work.sh" status "$@"
        ;;

    *)
        echo "Error: unknown verb '$verb'" >&2
        echo "  to start work on it: work start $verb" >&2
        exit 1
        ;;
esac

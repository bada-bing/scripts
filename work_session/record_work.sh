#!/usr/bin/env bash
#
# record_work - one gesture for "I am working on X".
#
# Timewarrior is the record: the interval is the only place work is recorded, and
# the journal, the session and this script all read from it. Taskwarrior holds
# prospective work and is read for what a task is - never written.
#
# Takes a key and never asks a question; selection lives in work.sh.
#
# Usage:
#   record_work.sh start <what> [<time>] [<duration>] [--dry-run]
#   record_work.sh stop  [--dry-run]
#   record_work.sh status
#
# The journal's "# Plan" is a hint, authored by hand and only ever read. Nothing
# here writes a marker into it, so a marker cannot fall out of step with the
# record - the open interval is the only claim about what is being worked on.
#
# Resolving the task goes first, because it is the only step that can
# legitimately refuse; a failure there leaves nothing written anywhere else.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

verb="${1:-}"
shift || true

dry_run=false
key=""
at=""
duration=""
words=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        -*)        echo "Error: unknown option $1" >&2; exit 1 ;;
        *)         case "$words" in
                       0) key="$1" ;;
                       1) at="$1" ;;
                       2) duration="$1" ;;
                   esac
                   words=$((words + 1)) ;;
    esac
    shift
done

# Positional, because the shapes are checked rather than guessed at: an unquoted
# label would otherwise arrive as a key, a time and a duration, and be recorded
# under a name that says nothing.
if [[ "$words" -gt 3 ]]; then
    echo "Error: expected at most <what> <time> <duration>" >&2
    echo "  a label of several words needs quoting" >&2
    exit 1
fi

if [[ -n "$at" && ! "$at" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
    printf "Error: '%s' is not a time like 16:00\n" "$at" >&2
    echo "  a label of several words needs quoting" >&2
    exit 1
fi

# Hours and minutes, spelled h and m, and nothing else - the shape the journal
# already uses. Every other spelling is refused rather than interpreted, because
# the one that would be read differently is the dangerous one.
if [[ -n "$duration" && ! "$duration" =~ ^([0-9]+h([0-9]+m)?|[0-9]+m)$ ]]; then
    printf "Error: '%s' is not a duration like 2h, 2h30m or 45m\n" "$duration" >&2
    echo "  hours and minutes only, written h and m" >&2
    exit 1
fi

# Here "m" means minutes. To Timewarrior it means MONTHS, which is why it is never
# passed through - and it refuses a compound like 2h30min outright anyway. Total
# minutes is the one form it reads the same way we mean it.
duration_minutes() {
    local d="$1" h=0 m=0
    if   [[ "$d" =~ ^([0-9]+)h([0-9]+)m$ ]]; then h=${BASH_REMATCH[1]}; m=${BASH_REMATCH[2]}
    elif [[ "$d" =~ ^([0-9]+)h$ ]];         then h=${BASH_REMATCH[1]}
    elif [[ "$d" =~ ^([0-9]+)m$ ]];         then m=${BASH_REMATCH[1]}
    fi
    printf '%d' $((h * 60 + m))
}

duration_said=""
if [[ -n "$duration" ]]; then
    minutes=$(duration_minutes "$duration")
    if [[ "$minutes" -le 0 ]]; then
        printf "Error: '%s' is no time at all\n" "$duration" >&2
        exit 1
    fi
    duration_said="$duration"      # reported back as it was written, not converted
    duration="${minutes}min"
fi

# The render is the only thing here that touches the journal, so it owns its own
# dry run and prints its own diff. Nothing has to be threaded through a shared
# working copy any more, which is what several journal edits used to need.
render_opts=""
$dry_run && render_opts="--dry-run"

# Announced on stderr, so a redirection on the real command cannot swallow it.
run() {
    if $dry_run; then
        printf 'would: %s\n' "$*" >&2
        return 0
    fi
    "$@"
}

# The Taskwarrior description IS the task key, so a task is addressed by its
# exact description rather than by an id that renumbers. Taskwarrior is read for
# what a task is and never written: it holds prospective work, and the record of
# what happened belongs to Timewarrior alone.
task_for_key() {
    task status:pending export 2>/dev/null \
        | jq -r --arg key "$1" 'map(select(.description == $key)) | .[0] // empty'
}

# The interval's tags: the identity first, then the domain and whatever else the
# task carries - the same set the Taskwarrior hook used to assemble.
interval_tags_for() {
    printf '%%%s\n' "$1"
    printf '%s' "$2" | jq -r '[(.project // empty)] + (.tags // []) | .[]'
}

# Timewarrior's active state is the interval with no end, and at most one exists.
# dom.active.json is an error rather than an empty answer when nothing is
# running, so the flag is tested first.
active_interval() {
    [[ "$(timew get dom.active 2>/dev/null || true)" == "1" ]] || return 1
    timew get dom.active.json 2>/dev/null
}

# One definition of the identity, shared with the status bar, so the two cannot
# disagree about what is being recorded. Prints "<kind>\t<identity>", or nothing.
active_identity() {
    "$SCRIPT_DIR/get_active_identity.sh"
}

# Just the identity, for a message that only needs to name what is running.
active_label() {
    active_identity | cut -f2
}

# An argument meant as a task must not quietly become an adhoc named after a typo,
# so two things are treated as evidence that a task was intended: a Logseq page
# exists for it, or it is shaped like a key. Anything else is prose, and prose is
# a label.
key_shaped() {
    [[ "$1" =~ ^[A-Za-z0-9]+[-_.][A-Za-z0-9]*[0-9]+$ ]]
}

# The id of an interval just recorded cannot be assumed to be @1: ids run newest
# first by start time, so something recorded earlier than today's other work lands
# further down the list. It is found by the start Timewarrior stored for it.
#
# The seconds are spelled out because date -j fills any field the format omits from
# the current time - "09:00" would become 09:00:09 and match nothing.
interval_id_starting_at() {
    local epoch stamp
    epoch=$(date -j -f '%Y-%m-%d %H:%M:%S' "$(date '+%Y-%m-%d') $1:00" '+%s') || return 1
    stamp=$(date -u -r "$epoch" '+%Y%m%dT%H%M%SZ') || return 1
    timew export today 2>/dev/null \
        | jq -r --arg s "$stamp" 'map(select(.start == $s)) | .[0].id // empty'
}

# Timewarrior refuses an overlap itself, and says what to do about it but not what
# is in the way. Its refusal stands as the single authority - this only explains it.
# The :adjust hint would make the overlap fit by reshaping whatever was already
# recorded, which is the one thing the record must never do quietly.
report_overlaps() {
    local from="$1" mins="$2" s e
    s=$(date -j -f '%Y-%m-%d %H:%M:%S' "$(date '+%Y-%m-%d') $from:00" '+%s') || return 0
    e=$((s + mins * 60))

    # jq compares in epoch seconds; the clock times are formatted here, because
    # Timewarrior stores UTC and these are read by someone thinking in local time.
    timew export today 2>/dev/null | jq -r --argjson s "$s" --argjson e "$e" '
        def stamp: strptime("%Y%m%dT%H%M%SZ") | mktime;
        def what: .annotation
                // ([.tags[]? | select(startswith("%"))] | first | if . then .[1:] else null end)
                // "an interval with no identity";
        .[]
        | select(((.start | stamp) < $e)
             and (((.end // "20991231T000000Z") | stamp) > $s))
        | [what, (.start | stamp), (if .end then (.end | stamp) else 0 end)] | @tsv' \
    | while IFS=$'\t' read -r label from_epoch to_epoch; do
        printf '  in the way: %s, %s to %s\n' "$label" \
            "$(date -r "$from_epoch" '+%H:%M')" \
            "$([[ "$to_epoch" == 0 ]] && printf 'now' || date -r "$to_epoch" '+%H:%M')" >&2
      done
}

case "$verb" in
    start)
        if [[ -z "$key" ]]; then
            echo "Usage: $(basename "$0") start <what> [<time>] [<duration>]" >&2
            echo "  to pick one: work start" >&2
            exit 1
        fi

        # A duration means the work is already over, so this records the past rather
        # than starting anything. It opens no interval, so it needs no session, and
        # it must not be refused because something else is running now - forgetting
        # to log this morning is exactly what it is for.
        past=false
        [[ -n "$duration" ]] && past=true

        # Start is never a way to reach a session, so any open interval refuses it.
        # The picker runs this same check before it asks, so reaching here with
        # something open means the operation was called directly.
        $past || "$SCRIPT_DIR/refuse_if_recording.sh" || exit 1

        # Dispatch by resolution rather than by a flag: a pending task means task
        # work, and anything else is an adhoc labelled with the argument itself.
        task_json=$(task_for_key "$key")

        if [[ -z "$task_json" ]]; then
            # A link names a page, and only a page with a pending task can be
            # started - whether or not the link looks like a task key. One rule for
            # every link, matching what the picker shows. And whether the argument
            # arrived as the link itself or as the key parsed out of one, the fact
            # worth saying is the same.
            link=""
            if [[ "$key" == *"[["*"]]"* ]]; then
                link="$key"
            else
                page_path=$("$SCRIPT_DIR/find_task_page.sh" "$key" 2>/dev/null) || page_path=""
                [[ -n "$page_path" ]] && link="[[$(basename "$page_path" .md)]]"
            fi

            if [[ -n "$link" ]]; then
                printf 'Error: %s is a link, not a task\n' "$link" >&2
                echo "  bootstrap the task if you meant to work on it" >&2
                exit 1
            fi

            if key_shaped "$key"; then
                printf 'Error: %s has no task and no page\n' "$key" >&2
                echo "  check the key" >&2
                exit 1
            fi

            # An adhoc carries no tags at all: the annotation is its label and its
            # identity. Neither verb takes an annotation, so labelling is a second
            # call - and a failure there takes the interval away again rather than
            # leaving work recorded that nothing can name.
            if $past; then
                if ! run timew track "$at" for "$duration" :yes >/dev/null; then
                    report_overlaps "$at" "$minutes"
                    exit 1
                fi
                if ! $dry_run; then
                    id=$(interval_id_starting_at "$at")
                    if [[ -z "$id" ]] || ! timew annotate "@$id" "$key" :yes >/dev/null 2>&1; then
                        [[ -n "$id" ]] && timew delete "@$id" :yes >/dev/null 2>&1
                        echo "Error: the interval could not be labelled, so it was removed" >&2
                        exit 1
                    fi
                fi
                "$SCRIPT_DIR/render_work_actuals.sh" $render_opts
                printf 'recorded: %s at %s for %s\n' "$key" "$at" "$duration_said"
                exit 0
            fi

            run timew start ${at:+"$at"} :yes >/dev/null || exit 1
            if ! run timew annotate @1 "$key" :yes >/dev/null; then
                run timew cancel :yes >/dev/null
                echo "Error: the interval could not be labelled, so it was cancelled" >&2
                exit 1
            fi

            # An adhoc has no repository and no page, and you are already somewhere
            # when you get interrupted. It is recorded, not inhabited.
            printf 'recording: %s%s\n' "$key" "${at:+ from $at}"
            exit 0
        fi

        tags=()
        while IFS= read -r tag; do
            [[ -n "$tag" ]] && tags+=("$tag")
        done < <(interval_tags_for "$key" "$task_json")

        # Past work needs no session: there is nowhere to go back to, and the day's
        # record is the only thing that has to change.
        if $past; then
            if ! run timew track "$at" for "$duration" "${tags[@]}" :yes >/dev/null; then
                report_overlaps "$at" "$minutes"
                exit 1
            fi
            "$SCRIPT_DIR/render_work_actuals.sh" $render_opts
            printf 'recorded: %s at %s for %s\n' "$key" "$at" "$duration_said"
            exit 0
        fi

        # Nothing can be open by this point, so the interval opens unconditionally.
        run timew start ${at:+"$at"} "${tags[@]}" :yes >/dev/null || exit 1

        # Bootstrapping is skipped entirely on a dry run - it would really
        # create the session, which is the opposite of dry.
        if $dry_run; then
            printf 'would: bootstrap and switch to session for %s\n' "$key" >&2
            exit 0
        fi
        session=$("$SCRIPT_DIR/task_session.sh" "$key") || exit 1

        # The task's own page belongs in the session it is worked in, not in
        # whatever window the picker happened to run from.
        "$SCRIPT_DIR/../dev-env/logseq_page.sh" --window "$session:edit" "$key" 2>/dev/null

        if [[ -z "${TMUX:-}" ]]; then
            tmux attach-session -t "$session:"
        else
            tmux switch-client -t "$session:"
        fi
        ;;

    stop)
        # The open interval knows what it is, so nothing has to be remembered
        # between starting and stopping.
        if ! active_interval >/dev/null; then
            echo "Nothing is being recorded" >&2
            exit 0
        fi
        IFS=$'\t' read -r kind label <<< "$(active_identity)"

        # Closing the interval before rendering means the actuals include it.
        run timew stop :yes >/dev/null || exit 1
        "$SCRIPT_DIR/render_work_actuals.sh" $render_opts

        # Stopping records that the work happened and nothing more. Whether it is
        # finished is a separate, deliberate act, in Taskwarrior and on its page.
        [[ -n "${label:-}" ]] || echo "The interval carried no identity" >&2

        # The session outlives the interval on purpose: stopping records that the
        # work happened, it does not tear down where it happened. The command is
        # printed to copy, never run - and only when there is really a session to
        # destroy, so the naming rule drifting from task_session.sh shows up as a
        # missing hint rather than a wrong command.
        if [[ "${kind:-}" == "task" ]]; then
            session=$(printf '%s' "$label" | tr '.:' '--')
            tmux has-session -t="$session" 2>/dev/null \
                && printf '  to destroy its session: tmux kill-session -t %s\n' "$session"
        fi
        ;;

    status)
        # Says only what nothing else can say: what is being recorded, and for how
        # long. Where the session is, tmux already shows; what the journal thinks,
        # the journal no longer thinks anything about.
        interval=$(active_interval || true)
        IFS=$'\t' read -r kind label <<< "$(active_identity)"
        elapsed=$(timew get dom.active.duration 2>/dev/null || true)

        if [[ -z "$interval" ]]; then
            echo "work: nothing active"
        elif [[ -z "${label:-}" ]]; then
            printf 'work: an interval with no identity%s\n' "${elapsed:+ (${elapsed})}"
            printf '  tags: %s\n' "$(printf '%s' "$interval" | jq -r '.tags // [] | join(", ")')"
        else
            printf 'work: %s%s%s\n' "$label" "${elapsed:+ (${elapsed})}" \
                "$([[ "$kind" == "adhoc" ]] && printf ' [adhoc]')"
        fi
        ;;

    *)
        echo "Usage: $(basename "$0") start <task-key> | stop | status" >&2
        exit 1
        ;;
esac

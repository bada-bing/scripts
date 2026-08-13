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
#   record_work.sh start <task-key> [--dry-run]
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
words=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        -*)        echo "Error: unknown option $1" >&2; exit 1 ;;
        *)         key="$1"; words=$((words + 1)) ;;
    esac
    shift
done

# An adhoc's label is one argument. Several means it went unquoted, and taking the
# last word silently would record work under a name that says nothing.
if [[ "$words" -gt 1 ]]; then
    echo "Error: expected one argument - a task key, or a label in quotes" >&2
    exit 1
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

# A key-shaped argument was meant as a task, so failing to resolve it is an error
# rather than a licence to record an adhoc called "CHARLIE_99". A Logseq page with
# that prefix says the same thing. Anything else is prose, and prose is a label.
looks_like_a_key() {
    [[ "$1" =~ ^[A-Za-z0-9]+[-_.][A-Za-z0-9]*[0-9]+$ ]] \
        || "$SCRIPT_DIR/find_task_page.sh" "$1" >/dev/null 2>&1
}

case "$verb" in
    start)
        if [[ -z "$key" ]]; then
            echo "Usage: $(basename "$0") start <task-key>" >&2
            echo "  to pick one: work start" >&2
            exit 1
        fi

        # Any open interval refuses the start - including one for this very key.
        # An interval forgotten about is invisible if restarting quietly succeeds,
        # and it keeps accruing: a sitting meant to be two hours becomes six. So
        # the elapsed time is reported, because noticing it is the point.
        #
        # This means start is never a way to reach a session. Navigation belongs
        # to the sessionizer, which touches no time at all.
        if active_interval >/dev/null; then
            IFS=$'\t' read -r current_kind current <<< "$(active_identity)"
            elapsed=$(timew get dom.active.duration 2>/dev/null || true)
            if [[ -n "${current:-}" ]]; then
                printf "Error: '%s' is already being recorded%s - stop it first\n" \
                    "$current" "${elapsed:+ (${elapsed})}" >&2
                # An adhoc has no session to be pointed at.
                [[ "${current_kind:-}" == "task" ]] \
                    && echo "  to reach its session without touching the record: tn" >&2
            else
                printf 'Error: an interval with no identity is already being recorded%s\n' \
                    "${elapsed:+ (${elapsed})}" >&2
                echo "  stop it first, or label it: timew annotate @1 '<what it was>'" >&2
            fi
            exit 1
        fi

        # Dispatch by resolution rather than by a flag: a pending task means task
        # work, and anything else is an adhoc labelled with the argument itself.
        task_json=$(task_for_key "$key")

        if [[ -z "$task_json" ]]; then
            if looks_like_a_key "$key"; then
                echo "Error: no pending Taskwarrior task described '$key'" >&2
                echo "  to record it as work with no task, give it a label in words" >&2
                exit 1
            fi

            # An adhoc carries no tags at all: the annotation is its label and its
            # identity. timew start takes tags only, so labelling is a second call -
            # and a failure there cancels the interval rather than leaving work
            # recorded that nothing can name.
            run timew start :yes >/dev/null || exit 1
            if ! run timew annotate @1 "$key" :yes >/dev/null; then
                run timew cancel :yes >/dev/null
                echo "Error: the interval could not be labelled, so it was cancelled" >&2
                exit 1
            fi

            # An adhoc has no repository and no page, and you are already somewhere
            # when you get interrupted. It is recorded, not inhabited.
            printf 'recording: %s\n' "$key"
            exit 0
        fi

        # Nothing can be open by this point, so the interval opens unconditionally.
        tags=()
        while IFS= read -r tag; do
            [[ -n "$tag" ]] && tags+=("$tag")
        done < <(interval_tags_for "$key" "$task_json")

        run timew start "${tags[@]}" :yes >/dev/null || exit 1

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
        label=$(active_label)

        # Closing the interval before rendering means the actuals include it.
        run timew stop :yes >/dev/null || exit 1
        "$SCRIPT_DIR/render_work_actuals.sh" $render_opts

        # Stopping records that the work happened and nothing more. Whether it is
        # finished is a separate, deliberate act, in Taskwarrior and on its page.
        [[ -n "$label" ]] || echo "The interval carried no identity" >&2
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

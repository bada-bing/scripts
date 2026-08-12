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
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        -*)        echo "Error: unknown option $1" >&2; exit 1 ;;
        *)         key="$1" ;;
    esac
    shift
done

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
# disagree about what is being recorded.
active_key() {
    "$SCRIPT_DIR/get_active_identity.sh"
}

case "$verb" in
    start)
        if [[ -z "$key" ]]; then
            echo "Usage: $(basename "$0") start <task-key>" >&2
            echo "  to pick one: work start" >&2
            exit 1
        fi

        # Timewarrior would close whatever is open by itself, but silently - the
        # journal marker and the day's record would be left behind, which is the
        # drift this whole gesture exists to prevent. The test is whether *any*
        # interval is open, not whether an identified one is: an interval started
        # by hand has no identity and no journal entry, so closing it silently
        # would lose the most.
        current=""
        if active_interval >/dev/null; then
            current=$(active_key)
            if [[ "$current" != "$key" ]]; then
                if [[ -n "$current" ]]; then
                    echo "Error: '$current' is already being recorded - stop it first" >&2
                else
                    echo "Error: an interval with no identity is already being recorded" >&2
                    echo "  stop it first, or give it one: timew tag @1 %$key" >&2
                fi
                exit 1
            fi
        fi

        task_json=$(task_for_key "$key")
        if [[ -z "$task_json" ]]; then
            echo "Error: no pending Taskwarrior task described '$key'" >&2
            exit 1
        fi

        # Already recording it means the session is what is missing, so opening
        # the interval again is skipped rather than treated as an error.
        if [[ "$current" != "$key" ]]; then
            tags=()
            while IFS= read -r tag; do
                [[ -n "$tag" ]] && tags+=("$tag")
            done < <(interval_tags_for "$key" "$task_json")

            run timew start "${tags[@]}" :yes >/dev/null || exit 1
        fi

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
        key=$(active_key)

        # Closing the interval before rendering means the actuals include it.
        run timew stop :yes >/dev/null || exit 1
        "$SCRIPT_DIR/render_work_actuals.sh" $render_opts

        # Stopping records that the work happened and nothing more. Whether it is
        # finished is a separate, deliberate act, in Taskwarrior and on its page.
        [[ -n "$key" ]] || echo "The interval carried no identity" >&2
        ;;

    status)
        # Says only what nothing else can say: what is being recorded, and for how
        # long. Where the session is, tmux already shows; what the journal thinks,
        # the journal no longer thinks anything about.
        interval=$(active_interval || true)
        key=$(active_key)
        elapsed=$(timew get dom.active.duration 2>/dev/null || true)

        if [[ -z "$interval" ]]; then
            echo "work: nothing active"
        elif [[ -z "$key" ]]; then
            printf 'work: an interval with no identity%s\n' "${elapsed:+ (${elapsed})}"
            printf '  tags: %s\n' "$(printf '%s' "$interval" | jq -r '.tags // [] | join(", ")')"
        else
            printf 'work: %s%s\n' "$key" "${elapsed:+ (${elapsed})}"
        fi
        ;;

    *)
        echo "Usage: $(basename "$0") start <task-key> | stop | status" >&2
        exit 1
        ;;
esac

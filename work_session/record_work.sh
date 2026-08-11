#!/usr/bin/env bash
#
# record_work - one gesture for "I am working on X".
#
# Four systems each hold a piece of that fact: the journal holds what was
# planned, Taskwarrior which task is active, Timewarrior the interval, tmux the
# session. Moved by hand they drift, so this moves them together.
#
# Takes a key and never asks a question; selection lives in work.sh.
#
# Usage:
#   record_work.sh start <task-key> [--dry-run]
#   record_work.sh stop  [--later|--done] [--dry-run]
#   record_work.sh status
#
# stop closes the interval either way; --later and --done differ only in the
# marker left in today's journal. Both mean "for today" - neither completes the
# Taskwarrior task, which stays a deliberate act of its own.
#
# Taskwarrior goes first, because it is the only step that can legitimately
# refuse; a failure there leaves nothing written anywhere else.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BLOCK="$SCRIPT_DIR/journal_work_block.sh"

verb="${1:-}"
shift || true

dry_run=false
outcome="LATER"
key=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        --done)    outcome="DONE" ;;
        --later)   outcome="LATER" ;;
        -*)        echo "Error: unknown option $1" >&2; exit 1 ;;
        *)         key="$1" ;;
    esac
    shift
done

# Announced on stderr, so a redirection on the real command cannot swallow it.
# Only for commands with no dry run of their own; the scripts that take
# --dry-run are called directly, so their diffs reach the terminal.
# A dry run applies the journal edits to one working copy threaded through every
# call, then diffs it once. Several edits therefore show as the single combined
# change they would make, instead of each step diffed against the unedited file.
block_opts=""
work_file=""
if $dry_run; then
    work_file=$(mktemp -u "${TMPDIR:-/tmp}/work-journal.XXXXXX")
    block_opts="--work-file $work_file"
    trap '[[ -n "$work_file" ]] && rm -f "$work_file"' EXIT
fi

show_journal_diff() {
    $dry_run || return 0
    "$BLOCK" diff $block_opts
}

# Announced on stderr, so a redirection on the real command cannot swallow it.
run() {
    if $dry_run; then
        printf 'would: %s\n' "$*" >&2
        return 0
    fi
    "$@"
}

# The Taskwarrior description IS the task key, so a task is addressed by its
# exact description rather than by an id that renumbers.
uuid_for_key() {
    task status:pending export 2>/dev/null \
        | jq -r --arg key "$1" 'map(select(.description == $key)) | .[0].uuid // empty'
}

active_key() {
    task +ACTIVE export 2>/dev/null | jq -r 'sort_by(.id) | last | .description // empty'
}

case "$verb" in
    start)
        if [[ -z "$key" ]]; then
            echo "Usage: $(basename "$0") start <task-key>" >&2
            echo "  to pick one: work start" >&2
            exit 1
        fi

        current=$(active_key)
        if [[ -n "$current" && "$current" != "$key" ]]; then
            echo "Error: '$current' is already active - stop it first" >&2
            exit 1
        fi

        uuid=$(uuid_for_key "$key")
        if [[ -z "$uuid" ]]; then
            echo "Error: no pending Taskwarrior task described '$key'" >&2
            exit 1
        fi

        marker=$("$BLOCK" list | awk -F'\t' -v k="$key" '$2 == k { print $1; exit }')

        # Calling it done for today was a decision; starting again would erase it
        # silently. Clearing the marker is the way to change your mind.
        if [[ "$marker" == "DONE" ]]; then
            echo "Error: '$key' is DONE for today" >&2
            echo "  to work on it again: $BLOCK set-marker $key LATER" >&2
            exit 1
        fi

        # Already active means the session is what is missing, so starting the
        # task again is skipped rather than treated as an error.
        if [[ "$current" != "$key" ]]; then
            run task "$uuid" start >/dev/null || exit 1
        fi

        # Only stand down a NOW that belongs to something else - demoting this
        # entry just to mark it again would write twice and, on a dry run, show
        # the intermediate step without the correction that follows it.
        [[ "$marker" == "NOW" ]] || "$BLOCK" demote-now $block_opts
        "$BLOCK" set-marker "$key" NOW $block_opts

        # Bootstrapping is skipped entirely on a dry run - it would really
        # create the session, which is the opposite of dry.
        if $dry_run; then
            show_journal_diff
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
        key=$(active_key)
        if [[ -z "$key" ]]; then
            echo "Nothing is active" >&2
            exit 0
        fi

        uuid=$(uuid_for_key "$key")
        if [[ -z "$uuid" ]]; then
            echo "Error: active task '$key' is not pending - resolve it by hand" >&2
            exit 1
        fi

        # Closing the interval before rendering means the actuals include it.
        run task "$uuid" stop >/dev/null || exit 1
        "$SCRIPT_DIR/render_work_actuals.sh" $block_opts

        # --done means done for today, so it moves the journal marker and
        # nothing else. Completing the task in Taskwarrior is a separate,
        # deliberate act - the task is finished when its page says so, not
        # because a day's work on it ended.
        "$BLOCK" set-marker "$key" "$outcome" $block_opts
        show_journal_diff
        ;;

    status)
        # NOW means "running right now", so exactly one entry may carry it and
        # only while Taskwarrior agrees. Anything else is drift between the two,
        # and drift that is not reported is drift that gets believed.
        key=$(active_key)
        now_keys=$("$BLOCK" list | awk -F'\t' '$1 == "NOW" { print $2 }')
        now_count=$(printf '%s' "$now_keys" | grep -c . || true)

        drift=""
        if [[ "$now_count" -gt 1 ]]; then
            drift="$now_count entries are NOW: $(printf '%s' "$now_keys" | tr '\n' ' ')"
        elif [[ -n "$key" && "$now_keys" != "$key" ]]; then
            drift="Taskwarrior is running '$key' but the journal's NOW is '${now_keys:-none}'"
        elif [[ -z "$key" && -n "$now_keys" ]]; then
            drift="the journal says NOW '$now_keys' but nothing is running"
        fi

        if [[ -z "$key" ]]; then
            echo "work: nothing active"
        else
            elapsed=$(timew get dom.active.duration 2>/dev/null || true)
            printf 'work: %s%s\n' "$key" "${elapsed:+ (${elapsed})}"
            if [[ -n "$now_keys" ]]; then
                printf '  journal: NOW\n'
            else
                printf '  journal: no NOW entry today\n'
            fi

            session=$(printf '%s' "$key" | tr '.:' '--')
            if tmux has-session -t="$session" 2>/dev/null; then
                printf '  session: %s\n' "$session"
            else
                printf '  session: none\n'
            fi
        fi

        if [[ -n "$drift" ]]; then
            echo "Error: $drift" >&2
            echo "  work stop clears the marker, or set it by hand" >&2
            exit 1
        fi
        ;;

    *)
        echo "Usage: $(basename "$0") start <task-key> | stop [--later|--done] | status" >&2
        exit 1
        ;;
esac

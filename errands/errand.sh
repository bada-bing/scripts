#!/usr/bin/env bash
#
# errand - the command-line front door for errands: small work that is too small
# to be a task, so it has no page, no Taskwarrior entry and no key of its own.
#
# errand is to Logseq what work is to Timewarrior - the sanctioned writer for one
# system, knowing its conventions so they never have to be held in the head. One
# asymmetry: work owns Timewarrior and merely renders "# Work", so that block can
# always be rebuilt from the store. Logseq is this store. Nothing can rebuild a
# day's "# Plan", so errand writes with a care work does not need.
#
# Two places hold errands, and capture writes to one or the other:
#
#   the day's "# Plan"  the errands being done today, from either source
#   SOA/Errands            errands captured for later, a pool to draw from
#
# Neither is a staging area for the other. An errand captured for today is not
# passing through on its way anywhere, and the backlog is a second inlet into the
# day's block rather than a queue that feeds it.
#
# Usage:
#   errand.sh capture <text>             into today's "# Plan"
#   errand.sh capture < block            the same, with the errand's subtree
#   errand.sh capture --backlog <text>   into SOA/Errands instead
#   errand.sh capture --backlog < block
#   errand.sh pop                        the first backlog errand, into today
#   errand.sh complete <text>            mark it DONE in today's block
#   errand.sh add-chores                 every chore due today, into today
#   errand.sh rename <old> <new>         change an errand's text everywhere
#
# An errand with subitems is written as a block and appended verbatim, which is
# the one format both places take:
#
#   errand.sh capture "Answer the pipeline question"
#
#   errand.sh capture <<'EOF'
#   - Move shopping-profile-ui to the WFC subgroup
#   	- the agreement: https://wescalehq.slack.com/archives/C08L86RPS8Y/p1789728287891509
#   EOF
#
# Quote the heredoc marker so the shell leaves the text alone, and indent with a
# real tab - <<-EOF strips leading tabs and would leave two errands, not one.
#
# pop takes the first errand in the backlog and only the first. The page is
# hand-ordered and that order is the prioritisation, so the head is by definition
# what comes next and there is nothing to choose. Three errands means running it
# three times.
#
# A move is all or nothing. The errand is written into the journal first and
# removed from the backlog only once that has worked; if anything after the write
# fails, the write is taken back and the day is left as it was found. So a pop
# either moves the errand or changes nothing, and never loses it.
#
# complete marks an errand DONE where it stands and leaves everything nested
# under it as it is. The entry stays in the block: what becomes of it is decided
# once, at the day's sweep, over the whole block rather than an entry at a time.
#
# It closes the open Timewarrior interval when that interval is this errand, and
# touches the clock in no other case. Finishing an errand while its clock runs is
# the failure work already guards against - an interval forgotten about is
# invisible, and a sitting meant to be twenty minutes becomes three hours. The
# asymmetry is deliberate: work stop still completes nothing, because stopping
# means you stepped away, not that you are done.
#
# add-chores instantiates every chore due today. A chore is a class and the
# errand it becomes is an instance, so from that moment nothing distinguishes it
# from one captured by hand: it is worked, completed and swept the same way.
#
# A chore already in today's block is skipped, so running add-chores twice is
# running it once and nothing has to remember whether it ran. That is not
# tidiness: an errand is addressed by its exact text and a mark lands on every
# entry matching it, so two identical lines could never be completed apart. A
# chore wanted twice in a day is two chores, and two labels - "Check the activity
# feed 12h" and "Check the activity feed 16h" - which keeps them apart in the
# record too.
#
# rename changes an errand's text, which is its identity, so it is written in two
# stores at once: the entry in the day block and the annotation on every interval
# recorded against it. Changing one alone breaks both - complete would no longer
# find the running interval, and the record would keep the old wording. A task
# needs none of this, since its identity is %<key> and its label is resolved from
# the page when the day is rendered.
#
# The block is renamed first and the record follows it, which is the direction the
# two already run in: an interval takes its label from the errand. If any interval
# refuses, the ones already changed and the block are put back, so a rename either
# happens whole or changes nothing.
#
# Un-completing is not here. Deleting the DONE that complete wrote is a judgement
# made while reading the block, and rare enough that a verb would cost more than
# it saves.
#
# Capture takes no date. An errand says what to do and never when, so there is no
# day to name but today's; anything that has to happen at a time is a reminder.
#
# Nothing here touches the clock. Capture opens no session and leaves an open
# interval running, so an errand arriving mid-task interrupts nothing - which is
# what makes capturing it cheap enough to do at the moment it comes up.
#
# --dry-run applies nothing and prints the difference it would make.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JOURNAL="$SCRIPT_DIR/../work_session/journal_work_block.sh"
BACKLOG="$SCRIPT_DIR/errand_backlog.sh"
CHORES="$SCRIPT_DIR/errand_chores.sh"
ACTIVE="$SCRIPT_DIR/../work_session/get_active_identity.sh"
RECORD="$SCRIPT_DIR/../work_session/record_work.sh"
RENDER="$SCRIPT_DIR/../work_session/render_work_actuals.sh"

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
}

# True when today's "# Plan" holds an entry with exactly this text. list
# prints marker, key, annotation, text, so the text is the fourth field.
today_has() {
    "$JOURNAL" list "${@:2}" \
        | awk -F'\t' -v t="$1" '$4 == t { found = 1 } END { exit !found }'
}

# Takes back the journal write, so a move that cannot be finished leaves the day
# as it found it. Verified rather than assumed: remove reports nothing when it
# matches nothing, and an entry left behind is a line the reader has to know about.
undo_journal() {
    "$JOURNAL" remove "$1"
    if today_has "$1"; then
        printf 'Error: could not take it back out of today; delete by hand: %s\n' "$1" >&2
        return 1
    fi
    printf 'The errand is back in the backlog and out of today: %s\n' "$1" >&2
}

verb="${1:-}"
shift || true

case "$verb" in
    -h|--help) usage; exit 0 ;;
    "")        usage >&2; exit 1 ;;
esac

case "$verb" in
    capture)
        to_backlog=false
        opts=()
        args=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --backlog) to_backlog=true; shift ;;
                --dry-run) opts+=("$1"); shift ;;
                -*)
                    echo "Error: unknown option '$1'" >&2
                    usage >&2
                    exit 1
                    ;;
                *) args+=("$1"); shift ;;
            esac
        done

        if [[ ${#args[@]} -gt 1 ]]; then
            echo "Error: capture takes one errand; quote the text" >&2
            printf '  got: %s\n' "${args[*]}" >&2
            exit 1
        fi

        # Both destinations take the same two inputs - a text argument or a block
        # on stdin - so the argument list is handed on unchanged and stdin is
        # inherited by whichever one runs.
        if $to_backlog; then
            exec "$BACKLOG" add ${args[0]+"${args[0]}"} ${opts[@]+"${opts[@]}"}
        else
            exec "$JOURNAL" add ${args[0]+"${args[0]}"} ${opts[@]+"${opts[@]}"}
        fi
        ;;

    pop)
        dry_run=false
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) dry_run=true; shift ;;
                -*)
                    echo "Error: unknown option '$1'" >&2
                    usage >&2
                    exit 1
                    ;;
                *)
                    echo "Error: pop takes no argument; it takes the first errand" >&2
                    exit 1
                    ;;
            esac
        done

        # Read first. peek leaves the page as it is, so nothing has happened yet
        # if any of the checks below refuse.
        block=$("$BACKLOG" peek) || exit 1
        text=$(head -1 <<< "$block"); text="${text#- }"

        # An errand is addressed by its exact text, so a second entry reading the
        # same thing would be indistinguishable from this one - to the revert
        # below, and afterwards to errand complete. Refused rather than resolved:
        # which of two identical lines was meant is not a question to guess at.
        if today_has "$text"; then
            printf 'Error: today already has an errand reading: %s\n' "$text" >&2
            echo "  two entries with one text could not be told apart" >&2
            exit 1
        fi

        if $dry_run; then
            # One diff says both: the block added to the journal is exactly the
            # block the backlog loses, so a second diff would restate it.
            printf '%s\n' "$block" | "$JOURNAL" add --dry-run
            exit $?
        fi

        # Write, then delete. Up to here nothing has changed, so a refusal costs
        # nothing; past here every failure is undone before returning.
        printf '%s\n' "$block" | "$JOURNAL" add || exit 1

        # The backlog is read again before anything is removed from it, so pop
        # can only ever take the errand that was written into the journal.
        if ! check=$("$BACKLOG" peek) || [[ "$check" != "$block" ]]; then
            echo "Error: the backlog changed while the errand was being moved" >&2
            undo_journal "$text"
            exit 1
        fi

        if ! popped=$("$BACKLOG" pop); then
            echo "Error: the errand could not be removed from the backlog" >&2
            undo_journal "$text"
            exit 1
        fi

        # pop reports what it took, so this asserts what the check above already
        # established. It has nothing left to undo - the page is written - so it
        # prints what was removed rather than dropping it.
        if [[ "$popped" != "$block" ]]; then
            echo "Error: the backlog removed an errand other than this one:" >&2
            printf '%s\n' "$popped" >&2
            undo_journal "$text"
            exit 1
        fi

        printf '%s\n' "$block"
        ;;

    complete)
        opts=()
        args=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) opts+=("$1"); shift ;;
                -*)
                    echo "Error: unknown option '$1'" >&2
                    usage >&2
                    exit 1
                    ;;
                *) args+=("$1"); shift ;;
            esac
        done

        text="${args[0]:-}"
        if [[ -z "$text" || ${#args[@]} -gt 1 ]]; then
            echo "Error: complete takes one errand's exact text, quoted" >&2
            exit 1
        fi

        # Refused before the clock is touched, so a mistyped errand stops nothing.
        if ! today_has "$text"; then
            printf "Error: today has no errand reading: %s\n" "$text" >&2
            echo "  the text must match the entry in # Plan exactly" >&2
            exit 1
        fi

        # Only when the open interval is this errand. An interval on anything
        # else is someone else's work in progress and is left running.
        IFS=$'\t' read -r kind label < <("$ACTIVE" || true)
        if [[ "${kind:-}" == "adhoc" && "${label:-}" == "$text" ]]; then
            "$RECORD" stop ${opts[@]+"${opts[@]}"} || exit 1
        fi

        # Marked last: a mark that does not land leaves an errand still open with
        # its clock stopped, which running complete again puts right.
        "$JOURNAL" mark "$text" ${opts[@]+"${opts[@]}"} || exit 1
        ;;

    add-chores)
        dry_run=false
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) dry_run=true; shift ;;
                -*)
                    echo "Error: unknown option '$1'" >&2
                    usage >&2
                    exit 1
                    ;;
                *)
                    echo "Error: add-chores takes no argument" >&2
                    exit 1
                    ;;
            esac
        done

        due=$("$CHORES" due) || exit 1
        if [[ -z "$due" ]]; then
            echo "No chore is due today" >&2
            exit 0
        fi

        # A dry run threads every chore through one working copy, so the diff
        # shows the day as all of them together would leave it rather than each
        # one against the journal as it stands.
        block_opts=()
        if $dry_run; then
            work_file=$(mktemp -u "${TMPDIR:-/tmp}/errand-add-chores.XXXXXX")
            block_opts=(--work-file "$work_file")
            trap '[[ -n "${work_file:-}" ]] && rm -f "$work_file"' EXIT
        fi

        while IFS= read -r label; do
            [[ -n "$label" ]] || continue
            today_has "$label" ${block_opts[@]+"${block_opts[@]}"} && continue
            "$JOURNAL" add "$label" ${block_opts[@]+"${block_opts[@]}"} || exit 1
            printf '%s\n' "$label"
        done <<< "$due"

        if $dry_run; then
            "$JOURNAL" diff ${block_opts[@]+"${block_opts[@]}"}
        fi
        ;;

    rename)
        dry_run=false
        args=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) dry_run=true; shift ;;
                -*)
                    echo "Error: unknown option '$1'" >&2
                    usage >&2
                    exit 1
                    ;;
                *) args+=("$1"); shift ;;
            esac
        done

        old_text="${args[0]:-}"
        new_text="${args[1]:-}"
        if [[ -z "$old_text" || -z "$new_text" || ${#args[@]} -gt 2 ]]; then
            echo "Error: rename takes the errand as it reads now, then as it should read" >&2
            exit 1
        fi
        if [[ "$old_text" == "$new_text" ]]; then
            echo "Error: the two texts are the same" >&2
            exit 1
        fi

        if ! today_has "$old_text"; then
            printf 'Error: today has no errand reading: %s\n' "$old_text" >&2
            exit 1
        fi
        # Renaming onto an errand already there would leave two entries with one
        # identity, which nothing afterwards could tell apart.
        if today_has "$new_text"; then
            printf 'Error: today already has an errand reading: %s\n' "$new_text" >&2
            exit 1
        fi

        # Every interval, not only the one running: a closed sitting left under
        # the old annotation would split away into a record entry of its own.
        # A while-read rather than readarray: macOS ships bash 3.2, where the
        # latter is not a builtin and fails silently enough to rename one store
        # and not the other.
        recorded=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && recorded+=("$line")
        done < <(
            timew export :all 2>/dev/null \
                | jq -r --arg a "$old_text" '.[] | select(.annotation == $a) | [.id, .start] | @tsv'
        )

        # The block first: an interval takes its label from the errand, so that
        # is the direction the rename runs in too.
        "$JOURNAL" rename "$old_text" "$new_text" $($dry_run && echo --dry-run) || exit 1

        days=()
        renamed=()
        for entry in ${recorded[@]+"${recorded[@]}"}; do
            [[ -n "$entry" ]] || continue
            IFS=$'\t' read -r id start <<< "$entry"

            if $dry_run; then
                printf 'would: timew annotate @%s "%s"\n' "$id" "$new_text" >&2
            elif ! timew annotate "@$id" "$new_text" :yes >/dev/null; then
                printf 'Error: interval @%s could not be re-annotated\n' "$id" >&2
                # Put back what has already moved, the block included, so the
                # errand is left under one text rather than under two.
                for done_id in ${renamed[@]+"${renamed[@]}"}; do
                    timew annotate "@$done_id" "$old_text" :yes >/dev/null \
                        || printf 'Error: interval @%s is stuck on the new text\n' "$done_id" >&2
                done
                if "$JOURNAL" rename "$new_text" "$old_text"; then
                    printf 'Nothing was renamed: %s\n' "$old_text" >&2
                else
                    printf 'Error: the block still reads: %s\n' "$new_text" >&2
                fi
                exit 1
            fi
            renamed+=("$id")

            # Timewarrior stamps UTC and a journal day is local, so an evening
            # sitting belongs to the day it felt like, not the day it stores as.
            epoch=$(date -j -u -f '%Y%m%dT%H%M%SZ' "$start" '+%s' 2>/dev/null) || continue
            day=$(date -r "$epoch" '+%Y-%m-%d')
            [[ " ${days[*]-} " == *" $day "* ]] || days+=("$day")
        done

        for day in ${days[@]+"${days[@]}"}; do
            "$RENDER" "$day" $($dry_run && echo --dry-run) >/dev/null || exit 1
        done
        ;;

    *)
        echo "Error: unknown verb '$verb'" >&2
        usage >&2
        exit 1
        ;;
esac

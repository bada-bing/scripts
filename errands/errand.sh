#!/usr/bin/env bash
#
# errand - the command-line front door for errands: small work that is too small
# to be a task, so it has no page, no Taskwarrior entry and no key of its own.
#
# errand is to Logseq what work is to Timewarrior - the sanctioned writer for one
# system, knowing its conventions so they never have to be held in the head. One
# asymmetry: work owns Timewarrior and merely renders "# Work", so that block can
# always be rebuilt from the store. Logseq is this store. Nothing can rebuild a
# day's "# Errands", so errand writes with a care work does not need.
#
# Two places hold errands, and capture writes to one or the other:
#
#   the day's "# Errands"  the errands being done today, from either source
#   SOA/Errands            errands captured for later, a pool to draw from
#
# Neither is a staging area for the other. An errand captured for today is not
# passing through on its way anywhere, and the backlog is a second inlet into the
# day's block rather than a queue that feeds it.
#
# Usage:
#   errand.sh capture <text>             into today's "# Errands"
#   errand.sh capture < block            the same, with the errand's subtree
#   errand.sh capture --backlog <text>   into SOA/Errands instead
#   errand.sh capture --backlog < block
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

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
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

    *)
        echo "Error: unknown verb '$verb'" >&2
        usage >&2
        exit 1
        ;;
esac

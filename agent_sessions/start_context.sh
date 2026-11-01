#!/usr/bin/env bash
#
# start_context - what an agent is told as it starts on a topic.
#
# Plain text, in this order: the topic and its page; the topic's other
# sessions, with their times and what each did, from the store; where the
# work stands, the Task Progress step and the Action Plan item marked NOW,
# read off the page; and, while the window is still automatically named, a
# line asking the agent to name it. Without a topic only that last line is
# printed, when it applies, else nothing.
#
# Usage: start_context.sh <key-or-empty> <session-id> <automatic-rename 0|1>
#
# The hook returns this as additionalContext at every SessionStart, so it is
# read at a fresh start, a resume, /clear and compaction alike, and never on
# a prompt. The agent reads no transcript for it: the store and the page
# carry what it needs.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TASK_SKILL="$HOME/.claude/skills/task"
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

key="${1:-}" session_id="${2:-}" auto_rename="${3:-0}"

if [[ -n "$key" ]]; then
    page=$("$SCRIPT_DIR/../work_session/find_task_page.sh" "$key" 2>/dev/null)
    echo "Topic: $key, page $(basename "${page:-$key}" .md)."

    echo "Earlier sessions on $key, resumable by id:"
    sessions=$("$SCRIPT_DIR/agent_session.sh" list "$key" 2>/dev/null \
        | awk -F'\t' -v me="$session_id" 'NF < 6 || $4 != me' \
        | awk -F'\t' 'NF == 6 { printf "  %s to %s  %s  %s  %s\n", $1, $2, $3 " " $4, $5, $6; next } { print "  " $0 }')
    echo "${sessions:-  none yet}"

    step=$(python3 "$TASK_SKILL/get_task_progress.py" "$key" step 2>/dev/null)
    now=$([[ -n "$page" ]] && awk '
        /^- ## / { plan = 0 }
        /^\t- ### Action Plan/ { plan = 1; next }
        plan && /^\t\t- NOW / { sub(/^\t\t- NOW /, ""); print; exit }
    ' "$page")
    echo "Where the work stands: ${step:-no step (the page fails validation)}; Action Plan NOW: ${now:-none}."
fi

if [[ "$auto_rename" == "1" ]]; then
    echo "This tmux window is still automatically named. Name it once the subject is clear, after the role it serves or a two-word topic slug: tmux rename-window -t \"\$TMUX_PANE\" \"<name>\"."
fi

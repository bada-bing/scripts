#!/usr/bin/env bash
#
# Creates a tmux session and lays out its windows. Idempotent and detached: an
# existing session is left alone, and the client is never attached or switched.
#
# The layout is named by the caller rather than derived from the session name,
# which is what lets a session named for a task get its repository's layout.
#
# Usage: bootstrap_session.sh <session-name> <cwd> [layout]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SESSION_NAME="${1:-}"   # sourced layout scripts read this - do not rename
session_cwd="${2:-}"
layout="${3:-}"

if [[ -z "$SESSION_NAME" || -z "$session_cwd" ]]; then
    echo "Usage: $(basename "$0") <session-name> <cwd> [layout]" >&2
    exit 1
fi

if [[ ! -d "$session_cwd" ]]; then
    echo "Error: not a directory: $session_cwd" >&2
    exit 1
fi

LOCAL_ENV="${ENV_DIR:-$HOME/Developer/toolbox/private/env}"

# has-session -t '<name>' also matches '<name>-extra-words'; -t='<name>' is exact.
if tmux has-session -t="$SESSION_NAME" 2>/dev/null; then
    echo "$SESSION_NAME"
    exit 0
fi

tmux new-session -d -s "$SESSION_NAME" -c "$session_cwd"

# A requested layout with no script falls back to the built-in one, so $layout is
# corrected here to name whatever actually runs.
layout_script="$LOCAL_ENV/tmux/$layout.tmux.sh"
if [[ -z "$layout" || ! -f "$layout_script" ]]; then
    layout="default"
    layout_script=""
fi

tmux set-option -t "$SESSION_NAME" @layout "$layout"

if [[ -n "$layout_script" ]]; then
    source "$layout_script"   # a layout script owns the session entirely
else
    # Processes are started on demand by proc, one window each, so the session
    # carries no window for them. Index 1 is the assistant in every layout.
    tmux rename-window -t "$SESSION_NAME:1" "assistant"
    # onefetch errors out when the directory is not a repository, which is the
    # normal case for a task falling back to tasks/<key>.
    tmux new-window -t "$SESSION_NAME:" -n "edit" -c "$session_cwd" "sh -c 'git rev-parse --git-dir >/dev/null 2>&1 && /opt/homebrew/bin/onefetch; exec $SHELL -l'"
fi

echo "$SESSION_NAME"

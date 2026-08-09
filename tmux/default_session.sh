#!/usr/bin/env bash

SESSION_NAME="default"
SESSION_PATH="$TOOLBOX_DIR"

if ! tmux has-session -t=$SESSION_NAME 2>/dev/null; then
    tmux new-session -d -s $SESSION_NAME -c "$SESSION_PATH"

    tmux rename-window -t $SESSION_NAME:1 "assistant"
    tmux new-window -t $SESSION_NAME -n "run" -c "$SESSION_PATH"
fi

if [ -z "$TMUX" ]; then
    tmux attach-session -t $SESSION_NAME
else
    tmux switch-client -t $SESSION_NAME
fi

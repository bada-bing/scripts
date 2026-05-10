#!/usr/bin/env bash

SESSION_NAME="pages"
SESSION_PATH="$HOME/Documents/Logseq/KB"

if ! tmux has-session -t=$SESSION_NAME 2>/dev/null; then
    tmux new-session -d -s $SESSION_NAME -c "$SESSION_PATH"
    
    tmux rename-window -t $SESSION_NAME:1 "run" # rename the first window
    tmux new-window -t $SESSION_NAME -n "edit" -c "$SESSION_PATH"
    tmux send-keys -t $SESSION_NAME:edit "vv" C-m
fi

if [ -z "$TMUX" ]; then
    tmux attach-session -t $SESSION_NAME
else
    tmux switch-client -t $SESSION_NAME
fi

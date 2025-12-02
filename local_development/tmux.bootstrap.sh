#! /usr/bin/env bash

SESSION_NAME=$1

# Check if session-specific bootstrap script exists in the tmux directory
SCRIPT_PATH="$HOME/src/scripts/local_development/tmux/$SESSION_NAME.tmux.sh"
SESSION_PATH="$HOME/src/$SESSION_NAME"


cd $SESSION_PATH

# If there is a custom script use it too bootstrap the session, otherwise use the default approach
if [ -f "$SCRIPT_PATH" ]; then
    source "$SCRIPT_PATH"
    exit 0
else
    tmux rename-window -t $SESSION_NAME:1 "run" # rename the first window
    if [ -f "$HOME/Documents/toolbox/env/mprocs/$SESSION_NAME.yaml" ]; then
      tmux send-keys -t $SESSION_NAME:run "mprocs -c /Users/miki/Documents/toolbox/env/mprocs/$SESSION_NAME.yaml" C-m
    fi
    tmux new-window -t $SESSION_NAME -n "edit" "sh -c '/opt/homebrew/bin/onefetch; exec $SHELL -l'"
fi

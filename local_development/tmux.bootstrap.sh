#! /usr/bin/env bash

SESSION_NAME=$1
PROJECT=$2
LOCAL_ENV="${ENV_DIR:-$HOME/Developer/toolbox/private/env}"

# Check if session-specific bootstrap script exists in the local env tmux directory
SCRIPT_PATH="$LOCAL_ENV/tmux/$SESSION_NAME.tmux.sh"

# Fall back to reconstructing the path if not passed
if [[ -z "$PROJECT" ]]; then
    PROJECT="$HOME/Developer/src/$SESSION_NAME"
fi

# If there is a custom script use it too bootstrap the session, otherwise use the default approach
if [ -f "$SCRIPT_PATH" ]; then
    source "$SCRIPT_PATH"
    exit 0
else
    tmux rename-window -t $SESSION_NAME:1 "run" # rename the first window
    if [ -f "$LOCAL_ENV/mprocs/$SESSION_NAME.yaml" ]; then
      tmux send-keys -t $SESSION_NAME:run "mprocs -c $LOCAL_ENV/mprocs/$SESSION_NAME.yaml" C-m
    fi
    tmux new-window -t $SESSION_NAME -n "edit" -c "$PROJECT" "sh -c '/opt/homebrew/bin/onefetch; exec $SHELL -l'"
    tmux new-window -t $SESSION_NAME -n "assistant" -c "$PROJECT"
fi

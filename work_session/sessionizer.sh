#!/usr/bin/env bash

# TODO: check primagen's script, it is simpler and more elegant

# 0. Select session name
# - Get first level directories from all roots in PROJECTS_PATH and select one
# split colon-separated PROJECTS_PATH into an array (IFS=':' sets field separator for this command only; -ra reads into array without interpreting backslashes)
IFS=':' read -ra project_dirs <<< "${PROJECTS_PATH:-$HOME/Developer/src}"
session=$(find "${project_dirs[@]}" -maxdepth 1 -mindepth 1 -type d | fzf)
session_name=$(basename $session | tr . -)

if [[ -z "$session_name" ]]; then
    exit 1
fi

# ACTIVE_PROJECT is used for sketchybar and raycast extension (not perfect but good enough solution)
sed -i -e "s/^ACTIVE_PROJECT=.*/ACTIVE_PROJECT=$session_name/" ~/Developer/src/raycast-extensions/wa-2/.env

# 1. Setup a new tmux session with the selected name
# - Only create the session if it doesn't exist already
# [tmux caveat] has-session -t '<session_name>' will return true even if it finds '<session_name>-extra-words'
# - for exact lookup you need to use -t='<session_name>' (in that case it will not return true for '<session_name>-extra-words')
if ! tmux has-session -t=$session_name 2>/dev/null; then
    tmux new-session -d -s $session_name -c $session
    sh $HOME/Developer/toolbox/scripts/tmux/bootstrap_session.sh $session_name $session
fi

# 3. Attach to the selected session
if [ -z "$TMUX" ]; then
    # if not inside a tmux session
    tmux attach-session -t $session_name
else
     # if already inside a tmux session
    tmux switch-client -t $session_name
fi

# 1. Run tmux sessionizer
# 2. determine if session exists
# / if session doesnt exist
# A.1 create session (detached)
# A.2 bootstrap it (includes part covered by hydration)
# A.3 switch (attach) to it
# / if session exists
# B.1 (optional) hydrate the session
# B.2 switch to it

# bootstrap
# if there is a session specific config, bootstrap using it
# if there is no specific config, use default

# config
# session specific config (e.g., cart ui)
# 1.) send keys: start wa-2 - preprare working environment - print output in "edit window"
# 2.) start mprocs - prepare local development setup 
# 3.) (optional) - utils: tests, diagnostics, jenkins pipeline (could also be part of mprocs, but without autostart)

# layout (chould apply to all sessions)
# 2 windows: run and edit
# run for "run servers and commands"
# edit for "make changes": editor and lazygit and others?

# destructing a session should destroy the whole environment created by the wa2

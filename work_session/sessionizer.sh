#!/usr/bin/env bash
#
# Picks what to work on and switches to its session.
#
# This is the interactive layer only: it selects a target, hands it to a session
# operation, and switches the client. Creating and laying out a session lives in
# tmux/bootstrap_session.sh, which is callable without any picker. See
# CHARLIE_07.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Get first level directories from all roots in SRC_PATH and select one. IFS=':'
# sets the field separator for this command only; -ra reads into an array
# without interpreting backslashes.
IFS=':' read -ra src_roots <<< "${SRC_PATH:-$HOME/Developer/src}"
selection=$(find "${src_roots[@]}" -maxdepth 1 -mindepth 1 -type d | fzf)

if [[ -z "$selection" ]]; then
    exit 0
fi

# A place session is named for its repository, and uses that repository's layout
# when one is defined.
repo=$(basename "$selection" | tr . -)
session_name=$("$SCRIPT_DIR/../tmux/bootstrap_session.sh" "$repo" "$selection" "$repo") || exit 1

# ACTIVE_PROJECT is used for sketchybar and raycast extension (not perfect but good enough solution)
sed -i -e "s/^ACTIVE_PROJECT=.*/ACTIVE_PROJECT=$session_name/" ~/Developer/src/raycast-extensions/wa-2/.env

if [ -z "${TMUX:-}" ]; then
    tmux attach-session -t "$session_name"
else
    tmux switch-client -t "$session_name"
fi

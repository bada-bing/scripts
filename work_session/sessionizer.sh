#!/usr/bin/env bash
#
# Picks what to work on and switches to its session.
#
# Interactive layer only: it selects a target and switches the client. Creating
# a session lives in tmux/bootstrap_session.sh and work_session/task_session.sh,
# both callable without any picker. See CHARLIE_07.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

selection=$("$SCRIPT_DIR/select_work.sh")

if [[ -z "$selection" ]]; then
    exit 0
fi

IFS=$'\t' read -r kind value <<< "$selection"

case "$kind" in
    task)
        session_name=$("$SCRIPT_DIR/task_session.sh" "$value")
        ;;
    repo)
        # A place session is named for its repository, and uses that
        # repository's layout when one is defined.
        repo=$(basename "$value" | tr . -)
        session_name=$("$SCRIPT_DIR/../tmux/bootstrap_session.sh" "$repo" "$value" "$repo")
        ;;
    *)
        echo "Error: unknown selection kind '$kind'" >&2
        exit 1
        ;;
esac

if [[ -z "$session_name" ]]; then
    exit 1
fi

# ACTIVE_PROJECT is used for sketchybar and raycast extension (not perfect but good enough solution)
sed -i -e "s/^ACTIVE_PROJECT=.*/ACTIVE_PROJECT=$session_name/" ~/Developer/src/raycast-extensions/wa-2/.env

if [ -z "${TMUX:-}" ]; then
    tmux attach-session -t "$session_name"
else
    tmux switch-client -t "$session_name"
fi

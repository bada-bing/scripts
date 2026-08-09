#!/usr/bin/env bash
#
# Creates a session for a task, named after the task key. Its working directory
# comes from the task page's Source Repository, so correcting a drifted task is
# a page edit rather than a session rebuild.
#
# Idempotent and detached, like bootstrap_session.sh: never attaches, never
# switches, prints the session name. See CHARLIE_07.
#
# Usage: task_session.sh <task-key>

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TASKS_DIR="${TASKS_DIR:-$HOME/Developer/toolbox/tasks}"

task_key="${1:-}"

if [[ -z "$task_key" ]]; then
    echo "Usage: $(basename "$0") <task-key>" >&2
    exit 1
fi

# Resolves a Source Repository entry to a directory. An entry is a path when it
# is absolute or starts with ~, and a name looked up under SRC_PATH otherwise.
resolve_repo() {
    local entry="$1"

    if [[ "$entry" == /* || "$entry" == "~"* ]]; then
        local expanded="${entry/#\~/$HOME}"
        [[ -d "$expanded" ]] && printf '%s\n' "$expanded"
        return
    fi

    local roots root
    IFS=':' read -ra roots <<< "${SRC_PATH:-$HOME/Developer/src}"
    for root in "${roots[@]}"; do
        [[ -d "$root/$entry" ]] && { printf '%s\n' "$root/$entry"; return; }
    done
}

session_cwd=""
layout=""

# find_task_page.sh reports its own reason - missing or ambiguous - so its
# stderr is left alone rather than replaced with a guess here.
page=$("$SCRIPT_DIR/find_task_page.sh" "$task_key")

if [[ -n "$page" ]]; then
    main_repo=$("$SCRIPT_DIR/get_task_repos.sh" "$page" | head -1)

    if [[ -z "$main_repo" ]]; then
        echo "Warning: '$task_key' has no Source Repository on its page" >&2
    else
        session_cwd=$(resolve_repo "$main_repo")
        [[ -z "$session_cwd" ]] && \
            echo "Warning: repository '$main_repo' not found under SRC_PATH" >&2
    fi
fi

if [[ -n "$session_cwd" ]]; then
    # The repository's own layout applies, whatever the session is called.
    layout=$(basename "$session_cwd" | tr . -)
else
    session_cwd="$TASKS_DIR/$task_key"
    mkdir -p "$session_cwd"
    echo "Starting in $session_cwd" >&2
fi

# tmux reads '.' and ':' as target separators, so a key containing either would
# be unaddressable. Task keys have neither, making this a no-op in practice.
session_name=$(printf '%s' "$task_key" | tr '.:' '--')

"$SCRIPT_DIR/../tmux/bootstrap_session.sh" "$session_name" "$session_cwd" "$layout"

#!/usr/bin/env bash
#
# Starts mprocs unless another session is already running one for the same
# working tree. Two sessions on one repository would otherwise both autostart
# it, and the second one's port-binding processes fail in a way that looks like
# broken code rather than a duplicate.
#
# Sessions are disposable, so the answer is to close one - this just says which.
#
# Usage: ensure_single_mprocs.sh [config-path]
#
# Without an argument the config is derived from the working tree, so it can be
# typed by hand from anywhere inside a repository.

set -uo pipefail

LOCAL_ENV="${ENV_DIR:-$HOME/Developer/toolbox/private/env}"

here=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
config="${1:-$LOCAL_ENV/mprocs/$(basename "$here" | tr . -).yaml}"

if [[ ! -f "$config" ]]; then
    printf 'no mprocs config for %s (looked for %s)\n' "$(basename "$here")" "$config" >&2
    exit 1
fi
my_session=$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null)

# Panes running mprocs in another session, rooted in the same working tree.
owner=$(
    tmux list-panes -a -F '#{session_name}	#{window_name}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null \
    | while IFS=$'\t' read -r session window command path; do
        [[ "$command" == "mprocs" ]] || continue
        [[ "$session" != "$my_session" ]] || continue
        root=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$path")
        [[ "$root" == "$here" ]] && { printf '%s:%s\n' "$session" "$window"; break; }
    done
)

if [[ -n "$owner" ]]; then
    printf 'mprocs for %s is already running in %s\n' "$(basename "$here")" "$owner" >&2
    printf 'kill %s to run it here instead\n' "$owner" >&2
    exit 0
fi

exec mprocs -c "$config"

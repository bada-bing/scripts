#!/usr/bin/env bash
#
# Starts mprocs unless another session is already running the same config. The
# identity is the config, since a pane's directory says nothing about which
# mprocs it is running. Two sessions on one config would otherwise both
# autostart it, and the second one's port-binding processes fail in a way that
# looks like broken code rather than a duplicate.
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
config=$(cd "$(dirname "$config")" && printf '%s/%s' "$PWD" "$(basename "$config")")

my_session=$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null)

# The config an mprocs below $1 was started with. It may be the pane's own
# process or a child of its shell, so the subtree is walked.
mprocs_config() {
    ps -axo pid=,ppid=,command= \
    | awk -v root="$1" '
        {
            parent[$1] = $2
            line = $3
            for (i = 4; i <= NF; i++) line = line " " $i
            command[$1] = line
        }
        END {
            for (p in command) {
                if (command[p] !~ /(^|\/)mprocs( |$)/) continue
                for (q = p; q != "" && q != "0"; q = parent[q])
                    if (q == root) { print command[p]; exit }
            }
        }
    ' \
    | awk '{ for (i = 1; i < NF; i++) if ($i == "-c") { print $(i + 1); exit } }'
}

# Panes in another session already running mprocs on this config.
owner=$(
    tmux list-panes -a -F '#{session_name}	#{window_name}	#{pane_current_command}	#{pane_pid}' 2>/dev/null \
    | while IFS=$'\t' read -r session window command pid; do
        [[ "$command" == "mprocs" ]] || continue
        [[ "$session" != "$my_session" ]] || continue
        [[ "$(mprocs_config "$pid")" == "$config" ]] && { printf '%s:%s\n' "$session" "$window"; break; }
    done
)

if [[ -n "$owner" ]]; then
    printf 'mprocs for %s is already running in %s\n' "$(basename "$config" .yaml)" "$owner" >&2
    printf 'kill %s to run it here instead\n' "$owner" >&2
    exit 0
fi

exec mprocs -c "$config"

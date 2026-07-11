#!/usr/bin/env bash

# Show a delta-rendered `git diff` in a dedicated, reusable split pane in the
# current tmux window. First call splits the pane; later calls respawn the
# same one in place instead of piling up new panes.
#
# Usage: review_diff.sh [--toggle] [repo_path]   (repo_path defaults to $PWD)
# --toggle: if the pane is already open, close it instead of refreshing it.
#           Used by the tmux keybinding, so pressing it again closes the pane.
# Without --toggle (used when an agent calls this directly), the pane is
# always (re)opened with the latest diff.

set -euo pipefail

toggle=false
if [[ "${1:-}" == "--toggle" ]]; then
  toggle=true
  shift
fi

repo="${1:-$PWD}"
repo="$(cd "$repo" 2>/dev/null && pwd)" || {
  echo "review_diff.sh: '$1' is not a directory" >&2
  exit 1
}

title="review-diff"
window="$(tmux display-message -p '#{window_id}')"

# zsh -l (login shell) so .zprofile is sourced and PATH includes Homebrew's
# /opt/homebrew/bin (where delta lives) — a plain `bash -c` here silently
# fell back to plain unstyled git diff output (delta missing from PATH).
cmd="zsh -l -c '
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo not a git repo: $repo
elif [ -z \"\$(git diff)\" ]; then
  echo no diff to show
else
  git diff
fi
read -n 1 -s -p \"(press any key to close)\"
'"

existing="$(tmux list-panes -t "$window" -F '#{pane_id} #{pane_title}' \
  | awk -v t="$title" '$2==t {print $1; exit}')"

if [[ -n "$existing" ]]; then
  if $toggle; then
    tmux kill-pane -t "$existing"
  else
    tmux respawn-pane -k -t "$existing" -c "$repo" "$cmd"
  fi
else
  new_pane="$(tmux split-window -h -t "$window" -c "$repo" -P -F '#{pane_id}' "$cmd")"
  tmux select-pane -t "$new_pane" -T "$title"
fi

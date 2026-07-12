#!/usr/bin/env bash

# Open Logseq pages in a dedicated, reusable split pane in the current tmux
# window — same pattern as review_diff.sh: one pane per window (tagged via
# pane title), respawned in place instead of piling up new splits.
#
# The pane runs an fzf picker over pages/ and journals/ (most recently
# modified first), opens the selection in nvim, and returns to the picker
# when nvim exits. Esc/ctrl-c in the picker closes the pane.
#
# Usage: logseq_page.sh [--toggle] [query]
# --toggle: if the pane is already open, close it instead of refreshing it.
#           Used by the tmux keybinding, so pressing it again closes the pane.
# query:    initial fzf filter — e.g. a task ID like "WFC-1145". If it
#           matches exactly one page, that page opens directly (--select-1).
#           An agent can call this with a task ID to hand over its page.

set -euo pipefail

toggle=false
if [[ "${1:-}" == "--toggle" ]]; then
  toggle=true
  shift
fi

query="${1:-}"
kb="$HOME/Documents/Logseq/KB"
title="logseq-page"
window="$(tmux display-message -p '#{window_id}')"

# zsh -l so .zprofile is sourced and PATH includes Homebrew (fzf, bat, nvim).
cmd="zsh -l -c '
cd \"$kb\"
q=\"$query\"
while sel=\$(ls -t pages/*.md journals/*.md 2>/dev/null \
    | fzf --prompt=\"logseq> \" --query=\"\$q\" --select-1 \
          --preview=\"bat --style=plain --color=always {}\"); do
  nvim \"\$sel\"
  q=\"\"
done
'"

existing="$(tmux list-panes -t "$window" -F '#{pane_id} #{pane_title}' \
  | awk -v t="$title" '$2==t {print $1; exit}')"

if [[ -n "$existing" ]]; then
  if $toggle; then
    tmux kill-pane -t "$existing"
  else
    tmux respawn-pane -k -t "$existing" -c "$kb" "$cmd"
  fi
else
  new_pane="$(tmux split-window -h -t "$window" -c "$kb" -P -F '#{pane_id}' "$cmd")"
  tmux select-pane -t "$new_pane" -T "$title"
fi

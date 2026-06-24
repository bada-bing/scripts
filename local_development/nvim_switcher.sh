#!/usr/bin/env bash

# Find all panes running nvim across all tmux sessions and switch to the selected one.
# Format: session:window.pane  [window_name]  path

selected=$(
  tmux list-panes -a \
    -F "#{session_name}:#{window_index}.#{pane_index}  [#{window_name}]  #{pane_current_path}" \
    | awk -F'  ' '{ cmd="tmux display-message -p -t " $1 " \"#{pane_current_command}\""; cmd | getline c; close(cmd); if (c == "nvim") print $0 }' \
    | fzf --prompt="nvim > " --layout=reverse --border
)

if [[ -z "$selected" ]]; then
  exit 0
fi

target=$(echo "$selected" | awk '{print $1}')
tmux switch-client -t "$target"

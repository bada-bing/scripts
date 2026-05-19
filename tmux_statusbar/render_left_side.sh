#!/bin/sh

# This script renders the left side of the tmux status bar.
# It displays indicators for various tmux modes and ensures a minimum width.

# --- Configuration ---
MINIMUM_WIDTH=25

# --- Theme Variables ---
TMUX_MODE_PREFIX_FG="#292e42"
TMUX_MODE_PREFIX_BG="#7dcfff"  # Blue
TMUX_MODE_COPY_BG="#bb9af7"      # Purple
TMUX_MODE_ZOOM_BG="#41a6b5"       # Teal
TMUX_MODE_VIEW_BG="#e0af68"       # Yellow/Orange

# --- Arguments from tmux ---
client_prefix="$1"
pane_mode="$2"
window_zoomed_flag="$3"
session_name="$4"

# --- Logic ---
# 1. Determine the raw output based on mode priority
raw_output=""
if [ "$window_zoomed_flag" = "1" ]; then
  raw_output=$(printf "#[bold,bg=%s,fg=%s]   ZOOM" "$TMUX_MODE_ZOOM_BG" "$TMUX_MODE_PREFIX_FG")
elif [ "$client_prefix" = "1" ]; then
  raw_output=$(printf "#[bold,bg=%s,fg=%s]   TMUX" "$TMUX_MODE_PREFIX_BG" "$TMUX_MODE_PREFIX_FG")
elif [ "$pane_mode" = "copy-mode" ]; then
  raw_output=$(printf "#[bold,bg=%s,fg=%s]   COPY" "$TMUX_MODE_COPY_BG" "$TMUX_MODE_PREFIX_FG")
elif [ "$pane_mode" = "view-mode" ]; then
  raw_output=$(printf "#[bold,bg=%s,fg=%s]   VIEW" "$TMUX_MODE_VIEW_BG" "$TMUX_MODE_PREFIX_FG")
else
  # Default: show session name
  raw_output=$("$HOME/src/scripts/dev-env/tmux_session_color.sh" "$session_name")
fi

# 2. Calculate visible length (by stripping format characters)
visible_text=$(echo "$raw_output" | sed -E 's/#\[[^]]*\]//g')
visible_length=${#visible_text}

# 3. Calculate and create padding
padding=""
if [ "$visible_length" -lt "$MINIMUM_WIDTH" ]; then
    padding_length=$((MINIMUM_WIDTH - visible_length))
    if [ "$padding_length" -gt 0 ]; then
        padding=$(printf '%*s' "$padding_length")
    fi
fi

# 4. Print the final, padded output
printf "%s%s" "$raw_output" "$padding"
#!/bin/sh

# This script renders the left side of the tmux status bar.
# It displays indicators for various tmux modes and ensures a minimum width.

. "$(dirname "$0")/lib.sh"

# --- Configuration ---
MINIMUM_WIDTH=25

# --- Theme Variables ---
TMUX_MODE_PREFIX_FG="#292e42"
TMUX_MODE_PREFIX_BG="#7dcfff"  # Blue
TMUX_MODE_COPY_BG="#bb9af7"      # Purple
TMUX_MODE_ZOOM_BG="#41a6b5"       # Teal
TMUX_MODE_VIEW_BG="#e0af68"       # Yellow/Orange
ATTENTION_FG="#f7768e"            # Red - matches the window state marker

# --- Arguments from tmux ---
client_prefix="$1"
pane_mode="$2"
window_zoomed_flag="$3"
session_name="$4"

# --- Cache ---
# The key is every argument, so each mode indicator appears the instant tmux
# reports it - pressing the prefix asks for a combination never rendered
# before and therefore always renders fresh. Only the count of waiting
# windows can lag, and it already moved at status-interval.
CACHE_KEY="left-$client_prefix-$pane_mode-$window_zoomed_flag-$session_name"

get_cache "$CACHE_KEY" && exit 0

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
  raw_output=$("$HOME/Developer/toolbox/scripts/tmux_statusbar/session_color.sh" "$session_name")
fi

# 2. Append the attention indicator: how many windows are waiting on Miki,
#    across every session including the current one. Windows rather than
#    sessions, so the number matches the red dots one for one - the ones
#    visible in the current window list, plus however many are parked in
#    sessions that are not on screen. No #[default] here on purpose: the
#    background set by the branch above carries through, so the indicator
#    sits inside the same coloured block as the session name rather than
#    beside it.
waiting_windows=$(tmux list-windows -a -F '#{@window_state}' 2>/dev/null \
  | grep -c '^waiting$' | tr -d ' ')

if [ "${waiting_windows:-0}" -gt 0 ]; then
  raw_output=$(printf "%s#[fg=%s,bold]● %s " \
    "$raw_output" "$ATTENTION_FG" "$waiting_windows")
fi

# 3. Calculate visible length (by stripping format characters)
visible_length=$(measure_width "$(strip_format "$raw_output")")

# 4. Calculate and create padding
padding=""
if [ "$visible_length" -lt "$MINIMUM_WIDTH" ]; then
    padding_length=$((MINIMUM_WIDTH - visible_length))
    if [ "$padding_length" -gt 0 ]; then
        padding=$(printf '%*s' "$padding_length")
    fi
fi

# 5. Print the final, padded output
output=$(printf "%s%s" "$raw_output" "$padding")
set_cache "$CACHE_KEY" "$output"
printf '%s' "$output"
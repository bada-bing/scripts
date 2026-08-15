#!/bin/sh

# This script renders the right side of the tmux status bar.
# It ensures the output has a fixed width by truncating or padding,
# which allows for a consistently sized colored background.

# --- Configuration ---
MAX_TARGET_WIDTH=80    # cap on wide screens
LEFT_WIDTH=25          # must match MINIMUM_WIDTH in render_left_side.sh
MIN_CENTER_WIDTH=20    # columns to always leave for the window-list "tabs"

# --- Arguments from tmux ---
session_name="$1"
client_width="$2"

# --- Cache ---
# tmux re-runs this script on every status redraw, not once per
# status-interval, and an animated busy marker forces several redraws a
# second. Gathering the components costs about 100ms - almost all of it
# Taskwarrior and Timewarrior queries - which is far too much to pay per
# frame. So the assembled output is reused for a moment.
#
# The TTL matches status-interval: the bar is no more stale than it was
# before anything started forcing redraws. Everything shown here is a
# minute-resolution figure, so there is nothing to see at frame rate anyway.
#
# The key covers both arguments, so a resized client or a different session
# renders fresh rather than inheriting another one's width. A session name
# containing a slash simply never matches a cache file, which costs speed
# and nothing else.
CACHE_TTL=2s
CACHE_DIR="${TMPDIR:-/tmp}/tmux-statusbar-cache"
CACHE_FILE="$CACHE_DIR/right-$session_name-$client_width"

if [ -n "$(find "$CACHE_FILE" -mtime "-$CACHE_TTL" -print -quit 2>/dev/null)" ]; then
    cat "$CACHE_FILE"
    exit 0
fi
mkdir -p "$CACHE_DIR" 2>/dev/null

# --- Logic ---

# Shrink the right side on narrow terminals so the centered window list
# (tabs) always has room to render instead of being squeezed out entirely.
if [ -n "$client_width" ]; then
    available=$((client_width - LEFT_WIDTH - MIN_CENTER_WIDTH))
    if [ "$available" -lt 0 ]; then
        available=0
    fi
    if [ "$available" -gt "$MAX_TARGET_WIDTH" ]; then
        TARGET_WIDTH=$MAX_TARGET_WIDTH
    else
        TARGET_WIDTH=$available
    fi
else
    TARGET_WIDTH=$MAX_TARGET_WIDTH
fi

# 1. Gather the components
session_color=$($HOME/Developer/toolbox/scripts/tmux_statusbar/session_color.sh "$session_name" right)
task_progress=$($HOME/Developer/toolbox/scripts/tmux_statusbar/render_active_work.sh)
current_sitting=$($HOME/Developer/toolbox/scripts/tmux_statusbar/get_current_sitting.sh)
datetime=$(date '+%a, %b %e')
hostname="[$(hostname -s)]"

# 2. Assemble the content string
if [ -n "$current_sitting" ]; then
    content_string="$task_progress  ⏱ $current_sitting"
else
    content_string="$task_progress"
fi

# 3. Sanitize and calculate visible length
# The sed command removes tmux formatting sequences like #[...]
visible_text=$(echo "$content_string" | sed -E 's/#\[[^]]*\]//g')
visible_length=${#visible_text}

# 4. Pad or truncate the visible text to match the TARGET_WIDTH
# We add padding to the left to right-align the content.
if [ "$visible_length" -gt "$TARGET_WIDTH" ]; then
    # Truncate the string if it's too long
    final_text=$(echo "$visible_text" | cut -c 1-$((TARGET_WIDTH-1)))"…"
elif [ "$visible_length" -lt "$TARGET_WIDTH" ]; then
    # Pad with spaces if it's too short
    padding_length=$((TARGET_WIDTH - visible_length))
    padding=$(printf '%*s' "$padding_length")
    final_text="$padding$visible_text"
else
    final_text="$visible_text"
fi

# 5. Combine the session color with the final, width-adjusted text
# A reset `#[default]` is used to ensure formatting doesn't leak.
output=$(printf "%s%s#[default]" "$session_color" "$final_text")
printf '%s' "$output" > "$CACHE_FILE" 2>/dev/null
printf '%s' "$output"
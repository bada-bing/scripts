#!/bin/sh

# This script renders the right side of the tmux status bar.
# It ensures the output has a fixed width by truncating or padding,
# which allows for a consistently sized colored background.

# --- Configuration ---
TARGET_WIDTH=100

# --- Arguments from tmux ---
session_name="$1"

# --- Logic ---

# 1. Gather the components
session_color=$(~/src/scripts/dev-env/tmux_session_color.sh "$session_name" right)
task_progress=$(~/src/scripts/dev-env/get_active_task_progress.sh)
datetime=$(date '+%a, %b %e')
hostname="[$(hostname -s)]"

# 2. Assemble the content string
# The content will be the task progress (or "NO ACTIVE TASK") followed by the date.
content_string="$task_progress"

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
printf "%s%s#[default]" "$session_color" "$final_text"
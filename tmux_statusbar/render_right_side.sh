#!/bin/sh

# This script renders the right side of the tmux status bar.
# It ensures the output has a fixed width by truncating or padding,
# which allows for a consistently sized colored background.

. "$(dirname "$0")/lib.sh"

# --- Configuration ---
# The block is deliberately fixed-width: the window list is centred between
# the two sides, so a right side that grew with its content would shove the
# tabs sideways every time the tracked task changed. Empty colour is the price
# of tabs that stay where they were.
#
# What the width has to be, though, is per-screen. These two numbers were both
# too small to bind, which made the shrink below dead code: on a 129-column
# laptop it computed 84 and on a 220-column monitor 175, so the cap returned 80
# on both and the laptop rendered the same block as the monitor - leaving the
# window list 24 columns and truncating the window names.
MAX_TARGET_WIDTH=80    # cap on wide screens
LEFT_WIDTH=33          # the widest the left side gets: MINIMUM_WIDTH is 25, but
                       # a session name longer than that overflows it, and
                       # wescale_module_federation renders 33
MIN_CENTER_WIDTH=50    # columns to always leave for the window-list "tabs".
                       # Measured: a three-window task session needs 43, and
                       # this session (raycast-telltale, run, zsh) needs 49
RIGHT_PAD='  '         # kept clear at the end, so nothing touches the frame

# --- Arguments from tmux ---
session_name="$1"
client_width="$2"

# --- Cache ---
# The key covers both arguments, so a resized client or a different session
# renders fresh rather than inheriting another one's width.
CACHE_KEY="right-$session_name-$client_width"

get_cache "$CACHE_KEY" && exit 0

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

# 2. Assemble the content string
if [ -n "$current_sitting" ]; then
    content_string="$task_progress  ⏱ $current_sitting"
else
    content_string="$task_progress"
fi

# 3. Measure what that will occupy on the bar
visible_length=$(measure_width "$content_string")

# 4. Pad or truncate the visible text to match the TARGET_WIDTH
# We add padding to the left to right-align the content. RIGHT_PAD is taken out of
# the width rather than added to it, so the coloured block keeps its size and the
# content simply ends a couple of columns short of the frame.
INNER_WIDTH=$((TARGET_WIDTH - ${#RIGHT_PAD}))
[ "$INNER_WIDTH" -lt 0 ] && INNER_WIDTH=0

if [ "$INNER_WIDTH" -le 1 ]; then
    # Too narrow for even one column and an ellipsis, so the right side stands
    # down entirely and the window list keeps the columns.
    final_text=""
else
    if [ "$visible_length" -gt "$INNER_WIDTH" ]; then
        # A cut returns the content stripped of its formatting, since cutting a
        # formatted string could slice through a #[...] sequence and leave half
        # an escape on the bar. Nothing on the right side is styled today, so
        # nothing is lost - but this is the branch to revisit if that changes.
        #
        # A cut lands a column short whenever the budget ends mid-glyph, since a
        # two-column glyph with one column left is dropped rather than
        # overflowed. Measuring the result rather than assuming it filled the
        # budget is what lets the padding below close that gap.
        content_string=$(truncate_to_width "$content_string" $((INNER_WIDTH - 1)))"…"
        visible_length=$(measure_width "$content_string")
    fi

    # Pad on the left to right-align the content.
    padding_length=$((INNER_WIDTH - visible_length))
    padding=""
    [ "$padding_length" -gt 0 ] && padding=$(printf '%*s' "$padding_length")
    final_text="$padding$content_string"
fi

[ -n "$final_text" ] && final_text="$final_text$RIGHT_PAD"

# 5. Combine the session color with the final, width-adjusted text
# A reset `#[default]` is used to ensure formatting doesn't leak.
output=$(printf "%s%s#[default]" "$session_color" "$final_text")
set_cache "$CACHE_KEY" "$output"
printf '%s' "$output"
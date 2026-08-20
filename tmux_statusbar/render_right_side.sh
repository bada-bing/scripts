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
active_work=$($HOME/Developer/toolbox/scripts/tmux_statusbar/get_active_work.sh)
current_sitting=$($HOME/Developer/toolbox/scripts/tmux_statusbar/get_current_sitting.sh)

kind=$(printf '%s' "$active_work" | cut -f1)
identity=$(printf '%s' "$active_work" | cut -f2)
step=$(printf '%s' "$active_work" | cut -f3)
now_item=$(printf '%s' "$active_work" | cut -f4)

# 2. Assemble the segments, in the order they appear on the bar
#
# The priority is what the bar gives up first when the block cannot hold
# everything, and the elidable flag marks a segment that loses its tail rather
# than the whole of itself. The elapsed time is the most important because it
# is the one figure that moves, and the phase the least because the key and
# the NOW item already say where the task stands.
#
# Each segment carries its own leading separator, so dropping one takes its
# separator with it rather than leaving a glyph attached to nothing.
NEWLINE='
'
segments=""
add_segment() {
    segments="${segments}${segments:+$NEWLINE}$1$_TAB$2$_TAB$3"
}

case "$kind" in
    adhoc)
        add_segment 2 1 "$identity"
        ;;
    task)
        add_segment 2 1 "Task $identity"
        [ -n "$step" ] && add_segment 4 0 " ▶ Step $step"
        [ -n "$now_item" ] && add_segment 3 1 " ┋ NOW $now_item"
        ;;
    unlabelled)
        add_segment 2 1 "  UNLABELLED WORK"
        ;;
    *)
        add_segment 2 1 "  NO ACTIVE WORK"
        ;;
esac

[ -n "$current_sitting" ] && add_segment 1 0 "  ⏱ $current_sitting"

# 3. Fit them to the block
# RIGHT_PAD is taken out of the width rather than added to it, so the coloured
# block keeps its size and the content simply ends a couple of columns short of
# the frame.
INNER_WIDTH=$((TARGET_WIDTH - ${#RIGHT_PAD}))
[ "$INNER_WIDTH" -lt 0 ] && INNER_WIDTH=0

if [ "$INNER_WIDTH" -le 1 ]; then
    # Too narrow for even one column and an ellipsis, so the right side stands
    # down entirely and the window list keeps the columns.
    final_text=""
else
    final_text=$(printf '%s
' "$segments" | fit_to_width "$INNER_WIDTH")
fi

[ -n "$final_text" ] && final_text="$final_text$RIGHT_PAD"

# 5. Combine the session color with the final, width-adjusted text
# A reset `#[default]` is used to ensure formatting doesn't leak.
output=$(printf "%s%s#[default]" "$session_color" "$final_text")
set_cache "$CACHE_KEY" "$output"
printf '%s' "$output"
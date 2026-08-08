#!/bin/sh

# Records the state of a long-running process on the tmux window it runs in,
# so the status bar can mark which window is busy and which one wants you.
#
# Not specific to any tool: coding agents drive it from their hooks, but any
# wrapper script around slow work can call it too. The state is stored as a
# window-scoped user option, which the Tokyo Night theme renders in
# window-status-format and in choose-tree.
#
# Usage: set_window_state.sh busy|waiting|clear [target-pane]
#
# The target defaults to the calling process's own pane, which is what hooks
# want. Key bindings pass #{pane_id} explicitly, since run-shell does not
# inherit TMUX_PANE.

state="$1"
target="${2:-$TMUX_PANE}"

# Outside tmux there is no window to mark.
[ -z "$target" ] && exit 0

# Being asked for attention while Miki is already looking at the pane is not
# worth a marker - he can see it. Treat that as "seen" and clear instead, so
# a finished turn in the focused pane does not leave a red window behind.
if [ "$state" = "waiting" ]; then
    watched=$(tmux display-message -p -t "$target" \
        '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}' 2>/dev/null)
    [ "$watched" = "1" ] && state="clear"
fi

case "$state" in
    busy|waiting)
        tmux set-option -w -t "$target" @window_state "$state" 2>/dev/null
        ;;
    *)
        # Anything else, including no argument, clears the marker.
        tmux set-option -uw -t "$target" @window_state 2>/dev/null
        ;;
esac

exit 0

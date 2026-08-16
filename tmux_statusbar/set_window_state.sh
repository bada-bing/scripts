#!/bin/sh

# Records the state of a long-running process on the tmux window it runs in,
# so the status bar can mark which window is busy and which one wants you.
#
# Not specific to any tool: coding agents drive it from their hooks, but any
# wrapper script around slow work can call it too. The state is stored as a
# window-scoped user option, which the Tokyo Night theme renders in
# window-status-format and in choose-tree, and which Tell-Tale reads
# for its menu-bar marker and its Waiting list.
#
# Usage: set_window_state.sh busy|waiting|clear [target-pane]
#
# The target defaults to the calling process's own pane, which is what hooks
# want. Key bindings pass #{pane_id} explicitly, since run-shell does not
# inherit TMUX_PANE.

state="$1"
target="${2:-$TMUX_PANE}"

# A resumed session runs under the background daemon, which strips TMUX_PANE
# from the process the hooks fire in but leaves it on an ancestor. Inherit it
# from the nearest ancestor that still has one, so those hooks keep marking
# the window the session is being watched in.
pid=$$
while [ -z "$target" ] && [ "$pid" -gt 1 ]; do
    target=$(ps eww -o command= "$pid" 2>/dev/null | tr ' ' '\n' | sed -n 's/^TMUX_PANE=//p' | head -1)
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$pid" ] && break
done

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

# What the window carries now, so the nudge below can fire on changes only.
# Anything that is not one of the two known states counts as no state.
previous=$(tmux show-option -qvw -t "$target" @window_state 2>/dev/null)
case "$previous" in busy | waiting) ;; *) previous="" ;; esac

case "$state" in
    busy)
        tmux set-option -w -t "$target" @window_state busy 2>/dev/null
        # The busy marker animates, which needs a process pushing frames.
        # run-shell -b hands it to the tmux server, so it outlives the hook
        # that called this. Starting a second one is a no-op.
        tmux run-shell -b "$(dirname "$0")/spin_window_state.sh" 2>/dev/null
        ;;
    waiting)
        tmux set-option -w -t "$target" @window_state waiting 2>/dev/null
        ;;
    *)
        # Anything else, including no argument, clears the marker.
        tmux set-option -uw -t "$target" @window_state 2>/dev/null
        state=""
        ;;
esac

# The status bar reads the option itself, so it needs no telling. Surfaces
# outside tmux do: Tell-Tale's menu-bar marker polls, and a poll interval
# long enough to be cheap is also long enough to show a window as waiting
# after the wait ended. So push the change to it.
#
# Only on an actual transition. The busy path fires on every tool call of
# every agent, and waking Raycast that often to say nothing changed would
# cost more than the marker is worth. The interval still covers a nudge that
# does not land - Raycast being closed, the extension not installed - so
# failing here is not worth noticing.
if [ "$state" != "$previous" ]; then
    open -g "raycast://extensions/miki/telltale/status?launchType=background" 2>/dev/null
fi

exit 0

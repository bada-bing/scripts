#!/bin/sh

# Animates the busy marker in the status bar.
#
# tmux only re-evaluates the status bar every status-interval (one second at
# best, two here), and a format expression cannot see sub-second time - so an
# animation cannot come from the format alone. Something has to push frames.
#
# This is that pusher: it writes the current glyph into the global @spin option
# and forces a status redraw, at a rate the eye reads as motion. The theme's
# busy marker just renders #{@spin}, so the format stays trivial.
#
# It lives only as long as some window is busy. set_window_state.sh starts it
# when a window goes busy; it notices when the last one stops and exits. A
# single instance serves every window, so all busy windows spin in step.
#
# A frozen spinner is information too: it means the marker outlived the work
# that set it.

# Three interchangeable frame sets. The animator cares about one property
# only: every glyph must occupy exactly one column. The trail slot promises a
# fixed width, so a frame that renders wider than its neighbours shifts every
# window to its right - several times a second, which is far worse than no
# animation at all.
#
# East Asian width is what decides that, and it is a property of the
# character, not of the font. Narrow is always one column. Ambiguous means the
# terminal chooses, so those glyphs are only safe once seen working here.
#
#   braille  ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏   all Narrow. Ten frames, reads as a wheel
#                                    turning - steady rotation, no pulse.
#   stars    ∗ ✢ ✻ ✳               all Narrow. Four frames ordered by weight,
#                                    so it reads as a star twinkling. Brighter
#                                    and closer in weight to the waiting dot.
#   stars+   · ∗ ✢ ✻ ✳ ✽           the same four with the two Ambiguous
#                                    glyphs Claude Code also uses, widening
#                                    the ramp at both ends. tmux lays them
#                                    out one column wide and Ghostty draws
#                                    them the same, so the two agree - but
#                                    that agreement is a fact about this
#                                    setup, not about the characters. A
#                                    terminal that counts Ambiguous as two
#                                    columns will smear the bar; fall back to
#                                    the plain stars there.
# Too dynamic? The swing comes from the two extremes, not from the frame
# count - `·` nearly vanishes and `✽` lands heavy, so the eye reads a breath.
# Dropping both ends to '∗ ✢ ✻ ✳' keeps the same speed but flattens it into
# an even shimmer. Reduce there before touching FRAME_DELAY.
FRAMES='· ∗ ✢ ✻ ✳ ✽'

# The one knob worth turning. Every frame is a full status redraw, and tmux
# re-runs the bar's #() scripts on each one - so this sets the animation's
# price as much as its speed. Measured at 0.15: roughly a fifth of one core
# while something is busy, nothing at all when idle. Both render scripts
# cache their output for exactly this reason; without that cache a watchable
# frame rate costs more than a whole core.
FRAME_DELAY=0.15

# How many frames between "is anything still busy?" checks. Listing every
# window is far more expensive than writing one option, so it runs about once
# a second rather than once a frame.
CHECK_EVERY=8

# Only one animator. A second one would fight the first for the option and
# double the redraw rate for no extra motion.
running=$(tmux show-option -gqv @spinner_pid)
if [ -n "$running" ] && kill -0 "$running" 2>/dev/null; then
    exit 0
fi
tmux set-option -g @spinner_pid "$$" 2>/dev/null || exit 0

cleanup() {
    tmux set-option -gu @spinner_pid 2>/dev/null
    exit 0
}
trap cleanup INT TERM

count=0
while :; do
    for frame in $FRAMES; do
        # Both in one command: half the round trips, and the redraw can never
        # show a frame the option does not hold yet. A failure here means the
        # server is gone, which is also the signal to stop.
        tmux set-option -g @spin "$frame" \; refresh-client -S 2>/dev/null || cleanup

        count=$((count + 1))
        if [ $((count % CHECK_EVERY)) -eq 0 ]; then
            tmux list-windows -a -F '#{@window_state}' 2>/dev/null \
                | grep -q '^busy$' || cleanup
        fi

        sleep "$FRAME_DELAY"
    done
done

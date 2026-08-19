#!/bin/sh
#
# Shared helpers for the two status bar renderers. Sourced, never executed.
#
# Each side used to carry its own copy of the same three things: the cache
# probe, the strip that makes a formatted string measurable, and the
# measurement itself. Two copies of a cache is merely untidy. Two copies of a
# measurement is somewhere the sides can disagree about how wide the bar is,
# which is the one thing they both have to agree on - they are laid out against
# each other, so a column one side miscounts is a column the window list
# between them loses.

# The cache exists because tmux re-runs a renderer on every status redraw
# rather than once per status-interval, and an animated busy marker forces
# several of those a second. Gathering a side's content costs about 100ms,
# nearly all of it Taskwarrior and Timewarrior queries, which is far too much
# to pay per frame.
#
# The TTL matches status-interval, so the bar is no more stale than it was
# before anything began forcing redraws. Everything shown here is a
# minute-resolution figure, so there is nothing to see at frame rate anyway.
CACHE_TTL=2s
CACHE_DIR="${TMPDIR:-/tmp}/tmux-statusbar-cache"

# Prints the cached render for a key and succeeds, or prints nothing and fails.
#
# The key has to cover every input the render depends on, so that a client of a
# different width, or a different session, renders fresh rather than inheriting
# another one's answer. A key containing a slash simply never matches a file,
# which costs speed and nothing else.
get_cache() {
    _cache_file="$CACHE_DIR/$1"
    [ -n "$(find "$_cache_file" -mtime "-$CACHE_TTL" -print -quit 2>/dev/null)" ] || return 1
    cat "$_cache_file"
}

set_cache() {
    mkdir -p "$CACHE_DIR" 2>/dev/null
    printf '%s' "$2" > "$CACHE_DIR/$1" 2>/dev/null
}

# Drops tmux's #[...] formatting sequences, which occupy no columns.
#
# This is for measuring only. What gets printed is always the unstripped
# string: stripping to measure and then printing the stripped copy silently
# discards whatever colour the content carried.
strip_format() {
    printf '%s' "$1" | sed -E 's/#\[[^]]*\]//g'
}

# The width of an already-stripped string.
measure_width() {
    _text=$1
    printf '%s' "${#_text}"
}

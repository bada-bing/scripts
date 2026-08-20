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

# Measuring and cutting a formatted string, both in the columns tmux gives it.
#
# Characters are not columns: an emoji takes two, and counting it as one makes
# the rendered block a column wider than the size the layout was built around.
# The window list centred between the two sides is what pays for that.
#
# Which glyphs are wide was measured against tmux rather than read off the
# Unicode tables, because the two disagree - tmux gives U+23F1 WATCH one column
# where its East Asian Width class asks for two. Of everything the bar prints
# only the moon phases came back as two columns, and they are also the only
# glyphs above U+FFFF, hence the only ones UTF-8 stores in four bytes.
#
# So the walk below decodes UTF-8 by sequence length and charges a four-byte
# sequence two columns. awk is pinned to C so that it counts bytes whatever the
# caller's locale is, which is what makes the decoding predictable.
#
# Both entry points strip tmux's #[...] sequences first, since those occupy no
# columns. Stripping here rather than at the call site is deliberate: measuring
# a formatted string without stripping it is silently wrong, so the step that
# must not be forgotten is not left to whoever is calling.
#
# A negative limit measures; a limit of zero or more cuts to that many columns.
# One program serves both so that a cut can never disagree with a measurement
# about where the string ends.
_WALK='
function seqlen(s) {
    if (s ~ /^[\360-\367][\200-\277][\200-\277][\200-\277]/) return 4
    if (s ~ /^[\340-\357][\200-\277][\200-\277]/) return 3
    if (s ~ /^[\300-\337][\200-\277]/) return 2
    return 1
}
{
    gsub(/#\[[^]]*\]/, "")
    rest = $0
    columns = 0
    kept = ""
    while (length(rest) > 0) {
        n = seqlen(rest)
        w = (n == 4) ? 2 : 1
        if (limit >= 0 && columns + w > limit) break
        kept = kept substr(rest, 1, n)
        columns += w
        rest = substr(rest, n + 1)
    }
    if (limit >= 0) printf "%s", kept; else printf "%d", columns
}'

# The width a string will occupy on the bar.
measure_width() {
    [ -n "$1" ] || { printf '0'; return; }
    printf '%s' "$1" | LC_ALL=C awk -v limit=-1 "$_WALK"
}

# The longest prefix of a string fitting a column budget. A budget the string
# already fits comes back whole, stripped of its formatting.
truncate_to_width() {
    [ -n "$1" ] || return 0
    printf '%s' "$1" | LC_ALL=C awk -v limit="$2" "$_WALK"
}

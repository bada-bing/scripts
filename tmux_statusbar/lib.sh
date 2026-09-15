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
_TAB=$(printf '\t')

CACHE_TTL=2s
CACHE_DIR="${TMPDIR:-/tmp}/tmux-statusbar-cache"

# Prints the cached render for a key and succeeds, or prints nothing and fails.
#
# The key has to cover every input the render depends on, so that a client of a
# different width, or a different session, renders fresh rather than inheriting
# another one's answer. A key containing a slash simply never matches a file,
# which costs speed and nothing else.
get_cache() {
    cache_is_fresh "$1" || return 1
    read_cache "$1"
}

set_cache() {
    mkdir -p "$CACHE_DIR" 2>/dev/null
    printf '%s' "$2" > "$CACHE_DIR/$1" 2>/dev/null
}

# Whether a key's cached render is younger than the TTL.
cache_is_fresh() {
    [ -n "$(find "$CACHE_DIR/$1" -mtime "-$CACHE_TTL" -print -quit 2>/dev/null)" ]
}

# A key's cached render whatever its age, and nothing at all where there is
# none. Serving one that has gone stale is what lets a side answer within a
# frame however long gathering its content takes - see below for why a side
# that gathers on the render path cannot be relied on to answer at all.
read_cache() {
    cat "$CACHE_DIR/$1" 2>/dev/null
}

# Refreshing a cache from off the render path.
#
# tmux re-runs a status #() job on every redraw and replaces the one in flight
# rather than waiting for it, so a job taking longer than the gap between two
# redraws never finishes and so never writes anything. The spinner pushes a
# redraw every FRAME_DELAY while any window is busy, and gathering the right
# side costs twice that - so every renderer was killed part way, the cache
# stayed empty, and the bar went on painting whatever had last completed. A bar
# reading "NO ACTIVE WORK" with an interval open is the one thing
# get_active_work.sh exists to prevent, and this arrived at it by another road.
#
# So the cache is no longer an optimisation the render path may skip: it is the
# only thing the render path reads. The job reads a file and always finishes,
# and the gathering runs in a process tmux does not own. The bar can then be a
# redraw or two behind, and can no longer be wrong.
#
# Making the gathering merely faster than a frame was the alternative, and it
# ties being right to winning a race - one more query, or a larger graph to
# search, and the bar starts lying again with nothing to say so.

# Whether a refresh for a key is already under way. Only an optimisation, the
# lock being what actually admits one refresher, but it saves forking a process
# several times a second for it to find the lock taken.
refresh_running() {
    [ -d "$CACHE_DIR/.refresh-$1" ]
}

# Runs a command detached from the caller, so that tmux killing the job which
# started it leaves it running.
#
# The descriptors matter as much as the detachment: tmux reads a job's stdout
# and takes end-of-output for the job ending, so a background child holding
# that pipe open would leave the job looking alive and stop the next one from
# ever being started.
refresh_detached() {
    nohup "$@" >/dev/null 2>&1 </dev/null &
}

# Admits one refresher per key and turns the rest away.
#
# mkdir is the gate because it is atomic. A lock left behind by a refresher
# that was killed outright would wedge its key for good, so one older than any
# gathering could plausibly take is taken over rather than respected.
LOCK_TTL=30s

take_refresh_lock() {
    _lock="$CACHE_DIR/.refresh-$1"
    mkdir -p "$CACHE_DIR" 2>/dev/null
    mkdir "$_lock" 2>/dev/null && return 0
    [ -n "$(find "$_lock" -mtime "-$LOCK_TTL" -print -quit 2>/dev/null)" ] && return 1
    rmdir "$_lock" 2>/dev/null
    mkdir "$_lock" 2>/dev/null
}

release_refresh_lock() {
    rmdir "$CACHE_DIR/.refresh-$1" 2>/dev/null
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

# Fits a list of segments into a column budget, returning exactly that many
# columns.
#
# Segments arrive on stdin, one per line, in the order they appear on the bar:
#
#   <priority>	<elidable>	<text>
#
# Priority is a number where lower means more important. Elidable is 1 for a
# segment whose tail may be cut and 0 for one that is only ever kept whole.
#
# When the segments do not fit, the least important one goes, then the next,
# until they do. Reaching an elidable one cuts it to what is left instead of
# dropping it, since a segment that can lose its tail should lose only that.
# The last segment standing is always cut rather than dropped, so a budget too
# small for anything whole still says something.
#
# This is what keeps the elapsed time on the bar. It is the shortest segment
# and the most important, so it is the last thing that could go, where cutting
# the assembled line from the right took it first.
#
# A segment carries its own leading separator, so dropping one takes its
# separator with it and no dangling glyph is left behind.
fit_to_width() {
    _limit=$1
    _segments=$(cat)

    while [ -n "$_segments" ]; do
        [ "$(measure_width "$(_join_segments "$_segments")")" -le "$_limit" ] && break

        _victim=$(printf '%s\n' "$_segments" | sort -t"$_TAB" -k1,1nr | head -n 1)
        _priority=$(printf '%s' "$_victim" | cut -f1)
        _elidable=$(printf '%s' "$_victim" | cut -f2)
        _survivors=$(printf '%s\n' "$_segments" | awk -F"$_TAB" -v p="$_priority" '$1 != p')

        if [ "$_elidable" = "0" ] && [ -n "$_survivors" ]; then
            _segments=$_survivors
            continue
        fi

        # Cut it to whatever the segments it cannot displace have left over,
        # one column of which the ellipsis takes.
        _room=$((_limit - $(measure_width "$(_join_segments "$_survivors")") - 1))
        if [ "$_room" -lt 1 ]; then
            _segments=$_survivors
            continue
        fi

        _cut=$(truncate_to_width "$(printf '%s' "$_victim" | cut -f3-)" "$_room")
        _segments=$(printf '%s\n' "$_segments" \
            | awk -F"$_TAB" -v OFS="$_TAB" -v p="$_priority" -v t="$_cut" \
                  '$1 == p { $3 = t "\342\200\246" } { print }')
        break
    done

    _text=$(_join_segments "$_segments")
    _padding=$((_limit - $(measure_width "$_text")))
    [ "$_padding" -gt 0 ] && _text="$(printf '%*s' "$_padding")$_text"
    printf '%s' "$_text"
}

# The segments' texts, run together in the order given.
_join_segments() {
    printf '%s\n' "$1" | while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _rest=${_line#*"$_TAB"}
        printf '%s' "${_rest#*"$_TAB"}"
    done
}

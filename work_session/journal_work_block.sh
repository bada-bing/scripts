#!/usr/bin/env bash
#
# Reads and writes one heading block of a day's Logseq journal. This is the only
# script that edits journal text, so a block's shape is defined in one place
# rather than in every caller that wants to read or replace one.
#
# A journal holds two blocks about work, and they answer different questions:
#
#   # Errands  what got done today - small work too small to be a task, whether
#              captured by hand, taken from the backlog or instantiated from a
#              chore. Read and written both. Its order is the prioritisation, so
#              nothing sorts it, and DONE on an entry says it was completed.
#   # Work     where the time went, rendered from Timewarrior. Machine-owned:
#              render_work_actuals.sh replaces it wholesale.
#
# Neither is derivable from the other: an errand can take three intervals and not
# be done, and it can be done with no interval at all.
#
# An entry is a top-level child of the block, and anything indented under it
# belongs to it and travels with it. An entry is addressed by its exact text, or
# by task key where it opens with a [[page]] link - which is how # Work is
# rendered. A link further along the text is part of what the entry says.
#
# Usage:
#   journal_work_block.sh list                            [--block B] [--date D]
#   journal_work_block.sh annotate <key> <text>            [--block B] [--date D]
#   journal_work_block.sh add      <text>                  [--block B] [--date D]
#   journal_work_block.sh add      < block                 [--block B] [--date D]
#   journal_work_block.sh mark     <key-or-exact-text>     [--block B] [--date D]
#   journal_work_block.sh remove   <key-or-exact-text>     [--block B] [--date D]
#   journal_work_block.sh replace  <line>...               [--block B] [--date D]
#   journal_work_block.sh diff                             [--date D]
#
# --block defaults to Errands, the block a person edits. --date defaults to today.
# list prints TSV: marker, key, annotation, text - the marker column is empty on
# anything but a completed errand.
#
# Dry runs work by applying the real edits to a working copy and diffing it
# against the journal, so what is shown is what would happen - not a guess.
#
#   --work-file <path>  operate on that copy, creating it from the journal (or
#                       the template) on first use. Several calls threaded
#                       through one copy compose, which is what a caller
#                       making more than one edit needs.
#   diff                print the copy's difference from the journal.
#   --dry-run           shorthand for a single edit: use a private copy, diff
#                       it, discard it.

set -uo pipefail

LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

verb="${1:-}"
shift || true

date_arg=""
work_file=""
block="Errands"
dry_run=false
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --date)      date_arg="${2:-}"; shift 2 ;;
        --block)     block="${2:-}"; shift 2 ;;
        --work-file) work_file="${2:-}"; shift 2 ;;
        --dry-run)   dry_run=true; shift ;;
        *)           args+=("$1"); shift ;;
    esac
done

if [[ -z "$block" ]]; then
    echo "Error: --block needs a heading name, e.g. Errands or Work" >&2
    exit 1
fi

day="${date_arg:-$(date '+%Y-%m-%d')}"
if [[ ! "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Error: --date must be YYYY-MM-DD, got '$day'" >&2
    exit 1
fi

journal="$LOGSEQ_GRAPH_PATH/journals/${day//-/_}.md"

# Where edits land: the journal itself, a copy the caller threads between
# calls, or a private copy for a one-shot dry run.
owns_copy=false
if [[ -n "$work_file" ]]; then
    target="$work_file"
elif $dry_run; then
    target=$(mktemp -u "${TMPDIR:-/tmp}/journal-work-block.XXXXXX")
    owns_copy=true
else
    target="$journal"
fi

# Only the template's indented children belong in a journal, dedented one
# level; the property lines under its own heading are skipped. Logseq applies
# :default-templates only when it creates the page itself, so a journal written
# here has to render the same skeleton - read live, never copied.
render_template() {
    awk '
        /^template:: _DAILY_TEMPLATE_$/ { found = 1; next }
        found && !body && /^\t/         { body = 1 }
        found && body {
            if ($0 !~ /^\t/) exit
            sub(/^\t/, "")
            print
        }
    ' "$LOGSEQ_GRAPH_PATH/pages/_templates_.md"
}

# True once there is a block to edit - either the journal exists, or a working
# copy has already been started from it.
have_block() {
    [[ -f "$target" || -f "$journal" ]]
}

ensure_target() {
    [[ -f "$target" ]] && return 0

    if [[ -f "$journal" && "$target" != "$journal" ]]; then
        cp "$journal" "$target"
        return 0
    fi

    [[ "$target" == "$journal" ]] || echo "would create $journal from _DAILY_TEMPLATE_" >&2
    render_template > "$target"
    if [[ ! -s "$target" ]]; then
        rm -f "$target"
        echo "Error: could not render _DAILY_TEMPLATE_ from $LOGSEQ_GRAPH_PATH/pages/_templates_.md" >&2
        return 1
    fi
}

show_diff() {
    local from=/dev/null
    [[ -f "$journal" ]] && from="$journal"
    diff -u --label "$journal" --label "$journal (would become)" "$from" "$1" || true
}

# Shared vocabulary for the awk programs below. A block's heading sits at column
# 0 and loses its bullet when it is the file's first block; the block runs until
# the next line at column 0. Entries are its immediate "\t- " children -
# anything deeper belongs to an entry and is passed through.
read -r -d '' AWK_PRELUDE <<'PRELUDE'
function is_heading(l) {
    sub(/^-[[:space:]]*/, "", l)
    sub(/[[:space:]]+$/, "", l)
    return l == "# " BLOCK
}
function is_top_level(l)    { return l ~ /^[^[:space:]]/ }
function is_entry(l)        { return l ~ /^\t- / }

function marker_of(l,   m) {
    m = l
    sub(/^\t- /, "", m)
    if (m ~ /^(LATER|NOW|DONE) /) { sub(/ .*$/, "", m); return m }
    return ""
}

# An entry belongs to <key> when its link is [[key]] or [[key-...]]. Testing the
# substring rather than building a regex keeps dots and dashes in a task key
# from being read as regex operators.
function entry_for_key(l, key,   at, rest) {
    at = index(l, "[[" key)
    if (at == 0) return 0
    rest = substr(l, at + length(key) + 2, 1)
    return (rest == "]" || rest == "-")
}

# An entry with no [[page]] is addressed by its text - which is an errand's
# identity, so the marker is stripped off before comparing.
function entry_text(l) {
    sub(/^\t- /, "", l)
    sub(/^(LATER|NOW|DONE) /, "", l)
    return l
}
PRELUDE

# True when the file's last byte is a newline. Command substitution strips
# trailing newlines, so a final newline leaves nothing behind to test.
ends_with_newline() {
    [[ -s "$1" ]] && [[ -z "$(tail -c1 "$1")" ]]
}

# Applies an awk program to the target and writes the result back. Trailing
# arguments are awk options.
transform() {
    local program="$1"; shift
    ensure_target || return 1

    # Logseq writes a journal with no trailing newline, and awk terminates every
    # line it prints - so an edit would silently add one and every diff would
    # carry "\ No newline at end of file". Whatever the file had is restored.
    local had_newline=false
    ends_with_newline "$target" && had_newline=true

    local updated
    updated=$(mktemp) || return 1
    if ! awk -v BLOCK="$block" "$@" "$AWK_PRELUDE
$program" "$target" > "$updated"; then
        rm -f "$updated"
        return 1
    fi

    # Written through the same inode, so Logseq's watcher sees a modification
    # rather than a replacement and the file keeps its permissions.
    #
    # A failed write is reported: a caller that moves an errand here from
    # somewhere else deletes it there once this returns, so silence would lose it.
    if ! cat "$updated" > "$target"; then
        printf 'Error: could not write %s\n' "$target" >&2
        rm -f "$updated"
        return 1
    fi
    rm -f "$updated"

    if ! $had_newline && ends_with_newline "$target"; then
        truncate -s -1 "$target"
    fi

    if $owns_copy; then
        show_diff "$target"
        rm -f "$target"
    fi
}

case "$verb" in
    list)
        # A working copy is read when one exists, so a caller mid-sequence sees
        # the state it has built up rather than the journal on disk.
        source_file="$journal"
        [[ -f "$target" ]] && source_file="$target"
        [[ -f "$source_file" ]] || exit 0

        awk -v BLOCK="$block" "$AWK_PRELUDE"'
            is_heading($0)        { inblock = 1; next }
            inblock && is_top_level($0) { inblock = 0 }
            inblock && is_entry($0) {
                text = $0
                sub(/^\t- /, "", text)
                marker = marker_of($0)
                if (marker != "") sub(/^(LATER|NOW|DONE) /, "", text)

                # Only a link the entry opens with names a page. A link further
                # along - "set up [[CHARLIE_09]] next" - is part of what the
                # entry says, and leaves it an ordinary errand.
                key = ""; annot = ""
                if (match(text, /^\[\[[^]]+\]\]/)) {
                    link = substr(text, RSTART + 2, RLENGTH - 4)
                    annot = substr(text, RSTART + RLENGTH)
                    sub(/^[[:space:]]+/, "", annot)
                    # A key is itself hyphenated (WFC-1146, BOOK-1), so it ends
                    # at the number, not at the first dash of the page name.
                    if (match(link, /^[A-Za-z0-9]+[-_][0-9]+/))
                        key = substr(link, RSTART, RLENGTH)
                }
                printf "%s\t%s\t%s\t%s\n", marker, key, annot, text
            }
        ' "$source_file"
        ;;

    diff)
        [[ -f "$target" ]] || exit 0
        show_diff "$target"
        ;;

    annotate)
        key="${args[0]:-}"
        annot="${args[1]:-}"
        if [[ -z "$key" ]]; then
            echo "Usage: $(basename "$0") annotate <key> <text>" >&2
            exit 1
        fi
        # Nothing to annotate in a day that was never written.
        have_block || exit 0

        # The annotation replaces whatever trails the link, so re-running it
        # after a corrected Timewarrior interval overwrites rather than appends.
        transform '
            is_heading($0)        { inblock = 1; print; next }
            inblock && is_top_level($0) { inblock = 0 }
            inblock && is_entry($0) && entry_for_key($0, key) {
                if (match($0, /\[\[[^]]+\]\]/)) {
                    head = substr($0, 1, RSTART + RLENGTH - 1)
                    print (annot == "" ? head : head " " annot)
                    next
                }
            }
            { print }
        ' -v key="$key" -v annot="$annot"
        ;;

    add)
        # Two inputs, matching the errand backlog's. An argument is one entry's
        # text and gets the bullet and the indent it needs; a block on stdin is an
        # entry written out with its subtree, and is indented one level into the
        # block. Either way the text itself is carried verbatim, marker included
        # if the caller wrote one - which is how an entry with no [[page]] to look
        # up gets moved from one day to another.
        #
        # Lines are joined on a unit separator rather than newlines, since awk's
        # -v cannot carry one.
        us=$'\x1f'
        text="${args[0]:-}"
        if [[ -n "$text" ]]; then
            lines=$'\t- '"${text#- }"
        else
            # Not "block": that name is taken by the heading this script edits.
            piped=$(cat)
            if [[ -z "$piped" ]]; then
                echo "Usage: $(basename "$0") add <text>   (or pipe the block in)" >&2
                exit 1
            fi
            if [[ "$piped" != "- "* ]]; then
                echo "Error: a piped block must open with a top-level bullet" >&2
                printf '  got: %s\n' "$(head -1 <<< "$piped")" >&2
                exit 1
            fi
            lines=""
            while IFS= read -r line; do
                [[ -n "$lines" ]] && lines+="$us"
                lines+=$'\t'"$line"
            done <<< "$piped"
        fi

        transform '
            function emit(   n, i, a) {
                n = split(lines, a, SEP)
                for (i = 1; i <= n; i++) print a[i]
            }
            is_heading($0) { inblock = 1; print; next }
            inblock && is_top_level($0) {
                if (!added) { emit(); added = 1 }
                inblock = 0
            }
            { print }
            END { if (inblock && !added) emit() }
        ' -v lines="$lines" -v SEP="$us"
        ;;

    replace)
        # A projected block is written whole rather than patched: every existing
        # entry goes and the given lines take their place. With no lines the
        # block is emptied, which is the honest rendering of a day with no data.
        # Joined on a unit separator rather than newlines: awk's -v cannot carry
        # a newline, and a journal entry is a single line anyway.
        us=$'\x1f'
        lines=""
        for line in ${args[@]+"${args[@]}"}; do
            [[ -n "$lines" ]] && lines+="$us"
            lines+="$line"
        done

        transform '
            function emit(   n, i, a) {
                if (lines == "") return
                n = split(lines, a, SEP)
                for (i = 1; i <= n; i++) print "\t- " a[i]
            }
            is_heading($0) { inblock = 1; print; next }
            inblock && is_top_level($0) {
                if (!written) { emit(); written = 1 }
                inblock = 0
            }
            inblock && is_entry($0) { skip = 1; next }
            inblock && skip {
                if (is_entry($0) || is_top_level($0)) skip = 0
                else next
            }
            { print }
            END { if (inblock && !written) emit() }
        ' -v lines="$lines" -v SEP="$us"
        ;;

    mark)
        # Completion, written where the errand sits. Idempotent, so completing
        # something twice is not an error - but an entry that is not there is a
        # typo rather than a no-op, since the text is the errand's identity.
        key="${args[0]:-}"
        if [[ -z "$key" ]]; then
            echo "Usage: $(basename "$0") mark <key-or-exact-text>" >&2
            exit 1
        fi
        have_block || { printf 'Error: no %s block on %s\n' "$block" "$day" >&2; exit 1; }

        if ! "$0" list --block "$block" --date "$day" \
                ${work_file:+--work-file "$work_file"} \
             | awk -F'\t' -v k="$key" '$4 == k || $2 == k { found = 1 }
                                       END { exit !found }'; then
            printf 'Error: no entry in %s on %s: %s\n' "$block" "$day" "$key" >&2
            exit 1
        fi

        transform '
            is_heading($0) { inblock = 1; print; next }
            inblock && is_top_level($0) { inblock = 0 }
            inblock && is_entry($0) && (entry_for_key($0, key) || entry_text($0) == key) {
                if (marker_of($0) == "DONE") { print; next }
                sub(/^\t- /, "\t- DONE ")
                print; next
            }
            { print }
        ' -v key="$key"
        ;;

    remove)
        key="${args[0]:-}"
        if [[ -z "$key" ]]; then
            echo "Usage: $(basename "$0") remove <key-or-exact-text>" >&2
            exit 1
        fi
        have_block || exit 0

        # Selected by task key, or by its exact text when it has no [[page]] to
        # be keyed by. Anything indented under the entry belongs to it and goes
        # too.
        transform '
            is_heading($0) { inblock = 1; print; next }
            inblock && is_top_level($0) { inblock = 0 }
            inblock && is_entry($0) && (entry_for_key($0, key) || entry_text($0) == key) { skip = 1; next }
            inblock && skip {
                if (is_entry($0) || is_top_level($0)) skip = 0
                else next
            }
            { print }
        ' -v key="$key"
        ;;

    *)
        echo "Error: unknown verb '$verb'" >&2
        sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//' >&2
        exit 1
        ;;
esac

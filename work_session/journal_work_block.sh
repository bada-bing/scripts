#!/usr/bin/env bash
#
# Reads and writes the "# Work" block of a day's Logseq journal. This is the
# only script that edits journal text, so the block's shape is defined in one
# place rather than in every caller that wants to move a marker.
#
# Entries are addressed by task key - the ID prefix of the [[page]] link they
# carry. Plain-text entries have no key: they are listed, never touched.
#
# Usage:
#   journal_work_block.sh list                                 [--date D]
#   journal_work_block.sh set-marker <key> <LATER|NOW|DONE|->   [--date D]
#   journal_work_block.sh annotate   <key> <text>               [--date D]
#   journal_work_block.sh demote-now                            [--date D]
#   journal_work_block.sh diff                                  [--date D]
#
# --date defaults to today. list prints TSV: marker, key, annotation, text.
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
dry_run=false
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --date)      date_arg="${2:-}"; shift 2 ;;
        --work-file) work_file="${2:-}"; shift 2 ;;
        --dry-run)   dry_run=true; shift ;;
        *)           args+=("$1"); shift ;;
    esac
done

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

# Shared vocabulary for the awk programs below. The "# Work" heading sits at
# column 0 and loses its bullet when it is the file's first block; the block
# runs until the next line at column 0. Entries are its immediate "\t- "
# children - anything deeper belongs to an entry and is passed through.
read -r -d '' AWK_PRELUDE <<'PRELUDE'
function is_work_heading(l) { return l ~ /^-?[[:space:]]*# Work[[:space:]]*$/ }
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
PRELUDE

# Applies an awk program to the target and writes the result back. Trailing
# arguments are awk options.
transform() {
    local program="$1"; shift
    ensure_target || return 1

    local updated
    updated=$(mktemp) || return 1
    if ! awk "$@" "$AWK_PRELUDE
$program" "$target" > "$updated"; then
        rm -f "$updated"
        return 1
    fi

    # Written through the same inode, so Logseq's watcher sees a modification
    # rather than a replacement and the file keeps its permissions.
    cat "$updated" > "$target"
    rm -f "$updated"

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

        awk "$AWK_PRELUDE"'
            is_work_heading($0)        { inblock = 1; next }
            inblock && is_top_level($0) { inblock = 0 }
            inblock && is_entry($0) {
                text = $0
                sub(/^\t- /, "", text)
                marker = marker_of($0)
                if (marker != "") sub(/^(LATER|NOW|DONE) /, "", text)

                key = ""; annot = ""
                if (match(text, /\[\[[^]]+\]\]/)) {
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

    set-marker)
        key="${args[0]:-}"
        marker="${args[1]:-}"
        if [[ -z "$key" || -z "$marker" ]]; then
            echo "Usage: $(basename "$0") set-marker <key> <LATER|NOW|DONE|->" >&2
            exit 1
        fi
        case "$marker" in
            LATER|NOW|DONE|-) ;;
            *) echo "Error: marker must be LATER, NOW, DONE or - (clear)" >&2; exit 1 ;;
        esac

        # Inserting a new entry needs the page's full name, which only the page
        # itself knows; a key with no page is still recorded, under the key.
        page="$key"
        if page_path=$("$(cd "$(dirname "$0")" && pwd)/find_task_page.sh" "$key" 2>/dev/null); then
            page=$(basename "$page_path" .md)
        fi

        transform '
            function new_entry() {
                return "\t- " (marker == "-" ? "" : marker " ") "[[" page "]]"
            }
            is_work_heading($0) { inblock = 1; print; next }
            inblock && is_top_level($0) {
                if (!seen) { print new_entry(); seen = 1 }
                inblock = 0
            }
            inblock && is_entry($0) && entry_for_key($0, key) {
                seen = 1
                text = $0
                sub(/^\t- /, "", text)
                sub(/^(LATER|NOW|DONE) /, "", text)
                print "\t- " (marker == "-" ? "" : marker " ") text
                next
            }
            { print }
            END { if (inblock && !seen) print new_entry() }
        ' -v key="$key" -v marker="$marker" -v page="$page"
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
            is_work_heading($0)        { inblock = 1; print; next }
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

    demote-now)
        # No journal means no NOW to stand down.
        have_block || exit 0

        # Only one thing is in progress at a time, so starting a task stands
        # down whatever else still claims NOW.
        transform '
            is_work_heading($0)        { inblock = 1; print; next }
            inblock && is_top_level($0) { inblock = 0 }
            inblock && is_entry($0) && marker_of($0) == "NOW" {
                sub(/^\t- NOW /, "\t- LATER ")
            }
            { print }
        '
        ;;

    *)
        echo "Usage: $(basename "$0") list|set-marker|annotate|demote-now|diff [...]" >&2
        exit 1
        ;;
esac

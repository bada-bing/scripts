#!/usr/bin/env bash
#
# Reads and writes the errand backlog - the SOA/Errands page. This is the only
# script that edits it, so the store's shape is defined in one place rather than
# in every caller that wants to read or take an errand.
#
# The page carries no heading: it holds one kind of thing, so there is nothing
# for a heading to tell apart. An errand is a top-level block, and everything
# indented under it belongs to it - a subaction, a link, a note - and is never
# interpreted. peek and pop carry that subtree, so an errand taken from here
# arrives with whatever was already done to it.
#
# No state marker is read. A top-level DONE is only ever written into the
# journal's "# Errands", never onto this page, and a nested DONE is payload like
# any other nested line.
#
# Usage:
#   errand_backlog.sh list            each errand's text, in order
#   errand_backlog.sh peek            the first errand, with its subtree
#   errand_backlog.sh add <text>      append one errand, bulleted here
#   errand_backlog.sh add < block     append a written block verbatim
#   errand_backlog.sh pop             the first errand, printed and removed
#
# An errand with subitems goes in as a block. Typing the same lines into the page
# by hand is the other way to do it, and no worse: the format is the format,
# whoever writes it.
#
#   errand_backlog.sh add "Buy groceries"
#
#   errand_backlog.sh add <<'EOF'
#   - Buy groceries
#   	- milk
#   	- eggs
#   EOF
#
# Quote the heredoc marker so the shell leaves the text alone, and indent with a
# real tab - <<-EOF strips leading tabs and would leave three errands, not one.
#
# The order is the prioritisation, so nothing sorts: add appends, and the first
# errand is by definition what comes next.
#
# pop is the only thing here that deletes, and it deletes only the head. An
# errand that is simply not wanted any more is deleted by hand, the way the sweep
# is - a judgement made while reading the page, not a command.
#
# The chores page is not touched from here. A chore is a definition, written and
# changed by hand, and read when one is instantiated.
#
# --dry-run applies nothing and prints the difference it would make.

set -uo pipefail

LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# Logseq stores a namespaced page with the slash percent-encoded, so the name
# written in the graph and the name on disk are not the same string.
PAGE="SOA/Errands"
file="$LOGSEQ_GRAPH_PATH/pages/${PAGE//\//%2F}.md"

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
}

verb="${1:-}"
shift || true

case "$verb" in
    -h|--help) usage; exit 0 ;;
    "")        usage >&2; exit 1 ;;
esac

dry_run=false
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        *)         args+=("$1"); shift ;;
    esac
done

if [[ ! -f "$file" ]]; then
    echo "Error: no such page: $file" >&2
    exit 1
fi

# A top-level block sits at column 0 and its subtree is everything indented
# under it; a blank line is not column 0, so it travels with the block it falls
# inside - the same rule journal_work_block.sh applies to a journal entry.
# Frontmatter is passed over rather than parsed: a key: value line is never an
# entry anyway.
read -r -d '' AWK_PRELUDE <<'PRELUDE'
function is_top_level(l) { return l ~ /^[^[:space:]]/ }
function is_entry(l)     { return l ~ /^- / }
function entry_text(l) {
    sub(/^- /, "", l)
    sub(/[[:space:]]+$/, "", l)
    return l
}
PRELUDE

# An empty page counts as terminated: there is no last line to continue, so the
# first errand needs no separator before it and none is truncated after it.
ends_with_newline() {
    [[ -s "$1" ]] || return 0
    [[ -z "$(tail -c1 "$1")" ]]
}

empty_page() {
    printf 'Error: %s holds no errands\n' "$PAGE" >&2
    exit 1
}

# Writes a produced file back over the page, or diffs it when nothing is to be
# applied. Whatever the page had at its end is restored: Logseq writes some pages
# without a trailing newline, and adding one would show up in every later diff.
commit() {
    local produced="$1" had_newline=false
    ends_with_newline "$file" && had_newline=true

    if $dry_run; then
        diff -u --label "$file" --label "$file (would become)" "$file" "$produced" || true
        rm -f "$produced"
        return 0
    fi

    # Written through the same inode, so Logseq's watcher sees a modification
    # rather than a replacement and the file keeps its permissions.
    #
    # A failed write is reported: pop prints the errand it took, and a caller
    # storing that output would otherwise hold an errand this page still has.
    if ! cat "$produced" > "$file"; then
        printf 'Error: could not write %s\n' "$file" >&2
        rm -f "$produced"
        return 1
    fi
    rm -f "$produced"
    if ! $had_newline && ends_with_newline "$file"; then
        truncate -s -1 "$file"
    fi
}

head_block() {
    awk "$AWK_PRELUDE"'
        NR == 1 && /^---$/ { fm = 1; next }
        fm                 { if (/^---$/) fm = 0; next }
        !seen && is_entry($0)    { seen = 1; emit = 1; print; next }
        emit && is_top_level($0) { emit = 0 }
        emit                     { print }
        END { if (!seen) exit 3 }
    ' "$file"
}

case "$verb" in
    list)
        awk "$AWK_PRELUDE"'
            NR == 1 && /^---$/ { fm = 1; next }
            fm                 { if (/^---$/) fm = 0; next }
            is_entry($0)       { print entry_text($0) }
        ' "$file"
        ;;

    peek)
        head_block || empty_page
        ;;

    add)
        # Two inputs, because there are two callers. An argument is one errand's
        # text and gets the bullet it needs; a piped block is a whole errand with
        # its subtree, already written, and is appended verbatim - which is how an
        # errand comes back here without being taken apart and rebuilt.
        #
        # awk -v cannot carry a newline, so the block is appended here rather than
        # passed into a program.
        block="${args[0]:-}"
        if [[ -n "$block" ]]; then
            block="- ${block#- }"          # a bullet the caller wrote is not doubled
        else
            block=$(cat)
            if [[ -n "$block" && "$block" != "- "* ]]; then
                echo "Error: a piped block must open with a top-level bullet" >&2
                printf '  got: %s\n' "$(head -1 <<< "$block")" >&2
                exit 1
            fi
        fi
        if [[ -z "$block" ]]; then
            echo "Usage: $(basename "$0") add <text>   (or pipe the block in)" >&2
            exit 1
        fi

        produced=$(mktemp) || exit 1
        cat "$file" > "$produced"
        ends_with_newline "$produced" || printf '\n' >> "$produced"
        printf '%s\n' "$block" >> "$produced"
        commit "$produced"
        ;;

    pop)
        # Read first, then write, then print: the block reaches the caller only
        # once the page without it is safely on disk, so a failed write leaves the
        # page as it was and nothing is lost.
        block=$(head_block) || empty_page

        produced=$(mktemp) || exit 1
        awk "$AWK_PRELUDE"'
            NR == 1 && /^---$/ { fm = 1; print; next }
            fm                 { print; if (/^---$/) fm = 0; next }
            !seen && is_entry($0)    { seen = 1; skip = 1; next }
            skip && is_top_level($0) { skip = 0 }
            skip                     { next }
            { print }
        ' "$file" > "$produced" || { rm -f "$produced"; exit 1; }
        commit "$produced" || exit 1
        printf '%s\n' "$block"
        ;;

    *)
        echo "Error: unknown verb '$verb'" >&2
        usage >&2
        exit 1
        ;;
esac

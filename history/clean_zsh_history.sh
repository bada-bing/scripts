#!/usr/bin/env bash
#
# Clean up the zsh history file in place:
#   - trim surrounding whitespace
#   - drop blank lines
#   - remove duplicate commands, keeping the most recent occurrence and
#     preserving chronological order (so history recall stays intact)
#
# A backup of the original is written before anything is changed.
#
set -euo pipefail

# ZDOTDIR is set in .zprofile; fall back to the conventional location.
histfile="${ZDOTDIR:-$HOME/.config/zsh}/.zsh_history"
backup="${histfile}.bak"

if [[ ! -f "$histfile" ]]; then
  echo "zsh history file not found: $histfile" >&2
  exit 1
fi

cp -p "$histfile" "$backup"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

LC_ALL=C awk '
  {
    line = $0
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line == "") next
    n++
    order[n]   = line
    last[line] = n
  }
  END {
    for (i = 1; i <= n; i++)
      if (last[order[i]] == i) print order[i]
  }
' "$histfile" > "$tmp"

before=$(wc -l < "$backup")
after=$(wc -l < "$tmp")

mv "$tmp" "$histfile"

echo "Cleaned $histfile"
echo "  $before -> $after lines (removed $((before - after)) duplicate/blank)"
echo "  Backup: $backup"

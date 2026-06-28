#!/usr/bin/env bash
# Usage: get_apple_note.sh [note_name] [format]
# Defaults to note "SOA" and format "html". Use "plain" for plaintext.

NOTE_NAME="${1:-SOA}"
PROPERTY=$([[ "${2:-html}" == "plain" ]] && echo "plaintext" || echo "body")

osascript <<EOF
tell application "Notes"
  set matchedNote to first item of (notes whose name is "$NOTE_NAME")
  get $PROPERTY of matchedNote
end tell
EOF

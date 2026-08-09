#!/bin/bash

# Check if an argument is provided
if [[ -z "$1" ]]; then
    echo "Usage: $0 <search-term>"
    exit 1
fi

# Search term from the first argument
SEARCH_TERM="$1"
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"

# Find the file and store the full path
FILE_PATH=$(find "$LOGSEQ_GRAPH_PATH/pages" -type f -name "*$SEARCH_TERM*")

# If a file was found, output just the filename
if [[ -n "$FILE_PATH" ]]; then
    # basename "$FILE_PATH"
    echo "$FILE_PATH"
fi

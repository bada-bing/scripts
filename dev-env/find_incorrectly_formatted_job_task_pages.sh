#!/bin/bash

# This is a prototype script to help me identify Logseq pages whose format is not to my liking.
# e.g., the properties are described in the `property:: value` format.

# The script finds Logseq pages that contain a specific tag, but only where the properties are written in the `key:: value` format.

# Check if a tag is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <tag>"
    exit 1
fi

LOGSEQ_KB_DIR="${HOME}/Documents/Logseq/KB"
TAG_TO_FIND="$1"

# Check if ripgrep is installed
if ! command -v rg &> /dev/null
then
    echo "ripgrep (rg) could not be found. Please install it to use this script."
    exit 1
fi

echo "Searching for Logseq files with 'tags:: ${TAG_TO_FIND}'..."
rg -l "tags:: ${TAG_TO_FIND}" "${LOGSEQ_KB_DIR}/pages" "${LOGSEQ_KB_DIR}/journals"

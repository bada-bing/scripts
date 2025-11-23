#!/bin/bash

# Fetch current Issue (i.e., Task) from the active branch 
# Repository is provided as the first argument `current-issue.sh ~/src/work-project-1`
# The script expects Issue id to be on the second position in the active branch (e.g., feature/WRK_1/task-description)

# Check if the directory parameter is provided
if [ -z "$1" ]; then
  echo "Need to provide directory: $0 <directory>"
  exit 11
fi

cd "$1" || { echo "Failed to change directory to $1"; exit 12; }

# Extract the ISSUE_KEY from the current Git branch
# Handles two formats:
# 1. feature/wfc-1039-set_up_an_endpoint (issue key with dash separator)
# 2. feature/wfc-1039/set_up_an_endpoint (issue key with slash separator)
BRANCH=$(git branch --show-current)
ISSUE_KEY=$(echo "$BRANCH" | grep -oE '[A-Za-z]+-[0-9]+' | head -n 1)

if [ -z "$ISSUE_KEY" ]; then
  echo "No issue key found in branch: $BRANCH" >&2
  exit 13
fi

echo $ISSUE_KEY
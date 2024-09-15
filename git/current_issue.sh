#!/bin/bash

# Fetch current Issue (i.e., Task) from the active branch 
# Repository is provided as the first argument `current-issue.sh ~/src/work-project-1`
# The script expects Issue id to be on the second position in the active branch (e.g., feature/WRK_1/task-description)

# Check if the directory parameter is provided
if [ -z "$1" ]; then
  echo "Need to provide directory: $0 <directory>"
  exit 1
fi

cd "$1" || { echo "Failed to change directory to $1"; exit 1; }

# Extract the ISSUE_KEY from the current Git branch
ISSUE_KEY=$(git branch --show-current | awk -F'/' '{print $2}')
echo $ISSUE_KEY

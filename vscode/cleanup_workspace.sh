#!/bin/bash

# Close all open editors (from previous session) - by simulating keyboard shortcut 'Cmd + K -> Cmd + W'

# Check if the workspace file exists
if [ ! -f "$1" ]; then
    echo "❌ Error: Workspace file '$1' does not exist"
    echo "Usage: $0 <workspace-file.code-workspace>"
    exit 1
fi

# Open the specific workspace
code "$1"
# Wait for the workspace to open before activating and cleaning
sleep 2

osascript -e 'tell application "Visual Studio Code" to activate' \
          -e 'delay 0.5' \
          -e 'tell application "System Events" to keystroke "k" using command down' \
          -e 'delay 0.1' \
          -e 'tell application "System Events" to keystroke "w" using command down'

echo "🔥 [vscode] close open editors from the previous session"
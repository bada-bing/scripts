#!/bin/bash

# Close all open editors (from previous session) - by simulating keyboard shortcut 'Cmd + K -> Cmd + W'

# [ -z ..] is a test expression, which tests if string "$1" is empty
[ -z "$1" ] && code || code "$1"

osascript -e 'tell application "Visual Studio Code" to activate' \
          -e 'delay 0.2' \
          -e 'tell application "System Events" to keystroke "k" using command down' \
          -e 'delay 0.1' \
          -e 'tell application "System Events" to keystroke "w" using command down'

echo "🔥 [vscode] close open editors from the previous session"
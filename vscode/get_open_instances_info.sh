#!/bin/bash

# Get the list of open vscode instances and run them through FZF
# Each line outputs the text in following format "<ACTIVE_EDITOR> — <WORKSPACE>[ - <PROFILE>]"

WINDOWS=$(code -s |  grep "|  Window" | awk -F'[()]' '{print $2, $4}' | tr -s ' ')

# choose one of the opened windows in vscode
SELECTED=$(echo "$WINDOWS" | fzf)
# separator is em dash (and not hyphen, i.e., minus)
echo "$SELECTED" | awk -F' — ' '{if (NF == 3) print $2; else if (NF == 2) print $1}'
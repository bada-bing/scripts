#!/bin/bash

# This script is used in tmuxinator projects to initiate the WA2 protocol

# the cleanup_workspace script does not work well when directly run from GO WA-2 application
# i.e., the keyboard shortcut is not executed and the vs code will not clear open editors in the workspace
~/Developer/src/wa-2/wa-2 "$1"
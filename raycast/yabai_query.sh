#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title query-window
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon ⛵
# @raycast.packageName yabai

# https://github.com/koekeishiya/yabai/wiki/Commands#querying-information

yabai -m query --windows --window last | jq '{title: .title, id: .id}'

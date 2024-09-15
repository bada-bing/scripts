#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title move window
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ⛵
# @raycast.argument1 { "type": "text", "placeholder": "Placeholder" }
# @raycast.packageName yabai

# Raycast Script Commands https://github.com/raycast/script-commands#api

# Yabai Move Window Commands https://github.com/koekeishiya/yabai/wiki/Commands#move-window

yabai -m window --space $1
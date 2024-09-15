#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title yabai-ratio-two-thirds
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ⛵
# @raycast.packageName yabai

# https://github.com/koekeishiya/yabai/wiki/Commands#querying-information
# https://github.com/koekeishiya/yabai/blob/af9d4cd3a96a7cfa02df1ff61d89414f5259b06e/doc/yabai.asciidoc?plain=1#L345-L346

yabai -m window --ratio 'abs:0.67'


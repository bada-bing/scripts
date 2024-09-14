#!/bin/bash

# Description: Reload localhost tab in Arc browser whenever FE build changes (i.e., assets-manifest.json changes) 
# it relies on fswatch and arc cli: https://github.com/pomdtr/arc

# the script is only an example, and there are multiple issues with it (e.g., what if there are 2 Arc windows)


FILE="../assets/asset-manifest.json"

fswatch -o "$FILE" | while read; do 
 echo "📦 asset-manifest changed"
 echo "🚛 FE build done"

 TABID=$(arc tab list | awk -F'\t' '$4 ~ /localhost/ {print $1}')

 # `arc tab select` $TABID # this command will give focus to the browser tab
 # `arc tab reload` # reloads only active tab

osascript -e "tell application \"Arc\" to reload tab $TABID of window 1"
 echo "reload tab $TABID"
 done

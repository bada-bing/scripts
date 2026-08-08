#!/bin/bash

session_name="$1"
side="$2"  # "right" or empty for left

hash=$(echo -n "$session_name" | md5sum | cut -c1-8)
color=$((16#${hash:0:6} % 216 + 16))

if [ "$side" = "right" ]; then
    # Right side - output the color code, with padding to extend the colored background and tmux will add the text
    # Outputs: 50 spaces with the colored background
    # printf "#[bg=colour%d,fg=colour0]%-50s" "$color" " "
    printf "#[bg=colour%d,fg=colour0]" "$color"
else
    # Left side - session name with icon
    session_upper=$(echo "$session_name" | tr '[:lower:]' '[:upper:]')
    printf "#[bg=colour%d,bold,fg=colour0]%-3s${session_upper}%-3s❯ #[nobold]" "$color"
fi
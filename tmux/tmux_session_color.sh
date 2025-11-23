#!/bin/bash
# ~/src/scripts/tmux/tmux_session_color.sh

session_name="$1"
side="$2"  # "right" or empty for left

hash=$(echo -n "$session_name" | md5sum | cut -c1-8)
color=$((16#${hash:0:6} % 216 + 16))

if [ "$side" = "right" ]; then
    # Right side - output the color code, with padding to extend the colored background and tmux will add the text
    # Outputs: 50 spaces with the colored background
    printf "#[bg=colour%d,fg=colour0]%-50s" "$color" " "
else
    # Left side - session name with icon
    session_upper=$(echo "$session_name" | tr '[:lower:]' '[:upper:]')
    printf "#[bg=colour%d,bold,fg=colour0]%-3s${session_upper}%-3s❯ #[nobold]" "$color"
fi


# Convert xterm-256 color to hex (and print them in the statusbar)
# For colors 16-231 (216-color cube)

# if [ "$color" -ge 16 ] && [ "$color" -le 231 ]; then
#     idx=$((color - 16))
#     r=$(( (idx / 36) * 51 ))
#     g=$(( ((idx % 36) / 6) * 51 ))
#     b=$(( (idx % 6) * 51 ))
#     printf "#%02x%02x%02x\n" "$r" "$g" "$b"
# fi
#!/bin/bash

# Useful ideas for batch renaming files


# ### 1. Replace the first underscore with a hyphen and save it as the new filename ### #
# --- en_US.json -> en-US.json

# - Loop through all files that match the pattern *_*.json
for file in *_*.json; do
    newfile=$(echo "$file" | sed 's/_/-/')

    # Rename the file
    mv "$file" "$newfile"
done


# ### 2. Remove Prefix ### #
# --- messages_en-US.json -> en-US.json
for file in messages_*.json; do
    # ${file#messages_} is a parameter expansion that removes the messages_ prefix from the filename.
    mv "${file}" "${file#messages_}"
done
#!/bin/bash

# The script operates under assumption that the active tasks in today's page are using references (block IDs)
# `NOW ((691b0c35-db06-44ab-8e48-0d0d1014e492))`

# Query LogSeq API for today's tasks marked as NOW
# Returns the content field from the first matching block
RESULT=$(curl -s --request POST \
  --url http://127.0.0.1:12315/api \
  --header 'authorization: Bearer d3183aef-d30a-4936-a370-018ee1b425ed' \
  --header 'content-type: application/json' \
  --header 'user-agent: vscode-restclient' \
  --data '{"method": "logseq.db.q", "args": ["(and (task NOW) <%today%>)"]}' | jq '.[0].content')

# Extract the block ID from the result
# Example: "NOW ((691b0c35-...))" -> "691b0c35-..."
# cut -d' ' -f2: gets the second word (the ID with parentheses)
# tr -d: removes parentheses, quotes, and backslashes
BLOCK_ID=$(echo $RESULT | cut -d' ' -f2 | tr -d '()[]\\"')

# Fetch the full block content using the extracted block ID
# jq -r: outputs raw string (converts \n to actual newlines, removes quotes)
# head -n 1: takes only the first line (before the "id::" line)

# Example: "691b0c35-..." -> "JIRA-ISSUE ✨ Feature Request 1"
BLOCK_CONTENT=$(curl -s --request POST \
  --url http://127.0.0.1:12315/api \
  --header 'authorization: Bearer d3183aef-d30a-4936-a370-018ee1b425ed' \
  --header 'content-type: application/json' \
  --header 'user-agent: vscode-restclient' \
  --data "{\"method\": \"logseq.Editor.getBlock\", \"args\": [\"$BLOCK_ID\"]}" | jq -r '.content' | head -n 1)

echo $BLOCK_CONTENT
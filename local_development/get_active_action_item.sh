#!/bin/sh

ISSUE_ID=$(sh ~/src/scripts/local_development/get_active_task.sh)

if [ -z "$ISSUE_ID" ]; then
  echo "🚸 WIP" # Active Task not properly set
else
  DESCRIPTION=$(curl -X POST -s \
    --url 'https://api.linear.app/graphql/api' \
    --header 'content-type: application/json' \
    --header "authorization: $LINEAR_API_KEY" \
    --data "{
      \"query\": \"query { issues(filter: { title: { contains: \\\"$ISSUE_ID\\\" } }) { nodes { id title description } } }\"
    }" | /opt/homebrew/bin/jq '.data.issues.nodes[0].description')


  ACTIVE_ITEM=$(echo "$DESCRIPTION" | grep -m 1 -e '- \[ \]' | sed 's/- \[ \] //')

  echo $ACTIVE_ITEM
fi
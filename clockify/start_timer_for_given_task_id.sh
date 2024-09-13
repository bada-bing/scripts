#!/usr/bin/env bash

# Description: add time entry - via rest api

# API_KEY=${1:-$CLOCKIFY_API_KEY}
API_KEY=$CLOCKIFY_API_KEY # available as env variable
WORKSPACES_URL=https://api.clockify.me/api/v1/workspaces
WORKSPACE_ID=$CLOCKIFY_MAIN_WORKSPACE_ID
PROJECT_ID=$PROFESSIONAL_PROJECT_ID # env variable

# curl -H "X-Api-Key: $API_KEY" https://api.clockify.me/api/v1/user | json_pp
# curl -H "X-Api-Key: $API_KEY" https://api.clockify.me/api/v1/workspaces/$WORKSPACE_ID/projects | json_pp
# curl -H "X-Api-Key: $API_KEY" https://api.clockify.me/api/v1/workspaces/$WORKSPACE_ID/projects/$PROJECT_ID/tasks | json_pp

# 1. Identify the task id
# 1.1. - get all tasks for the project
TASKS_URL="$WORKSPACES_URL/$WORKSPACE_ID/projects/$PROJECT_ID/tasks"
RESPONSE=$(curl -s -H "X-Api-Key: $API_KEY" $TASKS_URL)

# 1.2 - filter the task with the given id (e.g., from env variable)
TASK=$(echo "$RESPONSE" | jq -r ".[] | select(.id==\"$CLOCKIFY_DESIGN_INTERVIEW_PROTOCOL_ID\") | {id: .id, name: .name}")

# Extract the task id
TASK_ID=$(echo "$TASK" | jq -r '.id') # unnecessary in this example

# 2. Prepare Data
# 2.1 Get the current date
CURRENT_DATE=$(date -v-1H +'%Y-%m-%dT%H:%M:%SZ')

# 2.2. Set description for the task
DESCRIPTION="✍️ Design" # TODO Read current state/task from task manager

# 3. Start a new timer for the task
ADD_ENTRY_URL="$WORKSPACES_URL/$WORKSPACE_ID/time-entries"

# 3.1 - set the request body
read -r -d '' REQ_BODY << EOF
{
  "billable": true,
  "description": "$DESCRIPTION",
  "projectId": "$PROJECT_ID",
  "taskId": "$TASK_ID",
  "start": "$CURRENT_DATE",
  "type": "REGULAR"
}
EOF

# 4.3 - make curl post request to start a new timer
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Api-Key: $API_KEY" -H "Content-Type: application/json" -d "$REQ_BODY" $ADD_ENTRY_URL)
# -s for silent
# -o for output (ignore response - /dev/null)
# -w "%{http_code}" for write to stdout (this is saved in STATUS_CODE)
# -d "$REQ_BODY" for data

echo "Add time entry: Issue: $ISSUE_KEY; Task ID: $TASK_ID; Status: $STATUS_CODE"
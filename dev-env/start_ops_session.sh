#!/bin/bash
#
# Automates starting an ops session based on a selected Taskwarrior task.
# - Selects a task from project:ops
# - Finds the repo name from the associated Logseq file (if any)
# - Starts/attaches to a tmux session
# - Opens the corresponding VS Code workspace (if any)

set -e # Exit immediately if a command exits with a non-zero status.

# Get the number of currently active tasks.
active_count=$(task +ACTIVE count)
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/src/scripts}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/src}"
VSCODE_WORKSPACES_DIR="${VSCODE_WORKSPACES_DIR:-$HOME/Documents/toolbox/env/vs_code/workspaces}"
LOGSEQ_API_URL="${LOGSEQ_API_URL:-http://localhost:12315/api}"
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"


if [ "$active_count" -gt 0 ]; then
    echo "You already have an active task. Stop it before starting a new one."
    task active
    exit 1
fi

# --- 1. Select an ops task and find its file ---
TASK_DESC=$("$SCRIPTS_DIR/taskwarrior/select_ops_task.sh")

if [[ -z "$TASK_DESC" ]]; then
    echo "No task selected. Exiting."
    exit 0
fi

LOGSEQ_FILE=$("$SCRIPTS_DIR/taskwarrior/find_logseq_file.sh" "$TASK_DESC")

if [[ -z "$LOGSEQ_FILE" ]]; then
    echo "Error: Could not find Logseq file for task '$TASK_DESC'." >&2
    exit 1
fi

# --- Fetch Task Progress ---
echo "--> Fetching task progress from Logseq page:"
"$SCRIPTS_DIR/tracking_task_progress/get_logseq_task_progress.js" "$LOGSEQ_FILE"

# --- 2. Find the repository name and determine session name ---
REPO_NAME=$(grep "Source Repository" "$LOGSEQ_FILE" 2>/dev/null | awk -F': ' '{print $2}')
LOGSEQ_PAGE_NAME=$(basename "$LOGSEQ_FILE" .md)

SESSION_NAME=""
TMUX_C_PATH="$HOME"

if [[ -n "$REPO_NAME" ]]; then
    echo "--> Starting session for repository: $REPO_NAME"
    SESSION_NAME="$REPO_NAME"
    TMUX_C_PATH="$PROJECTS_DIR/$REPO_NAME"

    # --- 3. Open VS Code workspace ---
    WORKSPACE_PATH="$VSCODE_WORKSPACES_DIR/$REPO_NAME.code-workspace"
    if [[ -f "$WORKSPACE_PATH" ]]; then
        echo "--> Opening VS Code workspace..."
        code "$WORKSPACE_PATH"
    else
        echo "Warning: VS Code workspace not found at '$WORKSPACE_PATH'." >&2
    fi
else
    echo "--> 'Source Repository' not found in '$LOGSEQ_FILE'. Using page name for session."
    SESSION_NAME="$LOGSEQ_PAGE_NAME"
fi

# --- 4. Open Logseq page ---

# Check if the Logseq API is reachable and the required token is set
if [[ -n "$LOGSEQ_API_TOKEN" ]] && curl --max-time 1 -s "$LOGSEQ_API_URL" > /dev/null; then
    echo "--> Logseq API is running. Opening page '$LOGSEQ_PAGE_NAME' via API..."
    curl -s -X POST \
         -H "Authorization: Bearer $LOGSEQ_API_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{ \"method\": \"logseq.app.pushState\", \"args\": [\"page\", {\"name\": \"$LOGSEQ_PAGE_NAME\"}]}" \
         "$LOGSEQ_API_URL" > /dev/null
else
    # Fallback logic
    if [[ -z "$LOGSEQ_API_TOKEN" ]]; then
        echo "--> Warning: LOGSEQ_API_TOKEN environment variable is not set." >&2
    else
        echo "--> Logseq API is not running. Launching Logseq app..."
        open -a Logseq "$LOGSEQ_GRAPH_PATH"
    fi
    echo "--> Please open the page manually. Click here: logseq://graph/$(basename "$LOGSEQ_GRAPH_PATH")?page=$LOGSEQ_PAGE_NAME"
fi

# --- 5. Start or attach to tmux session ---
# First, ensure the session exists by creating it detached if it's not there.
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "--> Creating new detached tmux session..."
    # Create the new session in the background, starting in the likely project directory
    tmux new-session -d -s "$SESSION_NAME" -c "$TMUX_C_PATH"
fi

# Now, connect to the session in the appropriate way.
if [[ -z "$TMUX" ]]; then
    # We are outside of tmux, so attach to it.
    echo "--> Attaching to tmux session '$SESSION_NAME'..."
    tmux attach-session -t "$SESSION_NAME"
else
    # We are inside tmux, so switch to the target session.
    echo "--> Switching to tmux session '$SESSION_NAME'..."
    tmux switch-client -t "$SESSION_NAME"
fi

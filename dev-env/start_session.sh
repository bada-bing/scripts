#!/bin/bash
#
# Automates starting a development session based on a selected Taskwarrior task.
# Usage: start_session.sh <project>
#
# - Selects a task from project:<project>
# - Finds the repo name from the associated Logseq file, if present
# - Starts/attaches to a tmux session
# - Opens the corresponding VS Code workspace, when a repo is available

set -e # Exit immediately if a command exits with a non-zero status.

usage() {
    echo "Usage: $(basename "$0") <project>" >&2
    echo "Example: $(basename "$0") ops" >&2
}

PROJECT="${1:-}"

if [[ -z "$PROJECT" ]]; then
    usage
    exit 1
fi

if [[ "$PROJECT" == "-h" || "$PROJECT" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! "$PROJECT" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Error: project must contain only letters, numbers, dots, underscores, or hyphens." >&2
    exit 1
fi

SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/src/scripts}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/src}"
VSCODE_WORKSPACES_DIR="${VSCODE_WORKSPACES_DIR:-$HOME/Documents/toolbox/env/vs_code/workspaces}"
LOGSEQ_API_URL="${LOGSEQ_API_URL:-http://localhost:12315/api}"
LOGSEQ_GRAPH_PATH="${LOGSEQ_GRAPH_PATH:-$HOME/Documents/Logseq/KB}"
SELECT_TASK_SCRIPT="$SCRIPTS_DIR/taskwarrior/select_task.sh"

if [[ ! -x "$SELECT_TASK_SCRIPT" ]]; then
    echo "Error: task selector not found or not executable: $SELECT_TASK_SCRIPT" >&2
    exit 1
fi

# Get the number of currently active tasks.
active_count=$(task +ACTIVE count)

if [ "$active_count" -gt 0 ]; then
    echo "You already have an active task. Stop it before starting a new one."
    task active
    exit 1
fi

# --- 1. Select a task and find its file ---
TASK_DESC=$("$SELECT_TASK_SCRIPT" "$PROJECT")

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
REPO_NAME=$(awk -F': ' '/Source Repository/ {print $2; exit}' "$LOGSEQ_FILE" 2>/dev/null)
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

# Check if the Logseq API is reachable and the required token is set.
if [[ -n "$LOGSEQ_API_TOKEN" ]] && curl --max-time 1 -s "$LOGSEQ_API_URL" > /dev/null; then
    echo "--> Logseq API is running. Opening page '$LOGSEQ_PAGE_NAME' via API..."
    REQUEST_BODY=$(jq -cn --arg page "$LOGSEQ_PAGE_NAME" \
        '{method: "logseq.app.pushState", args: ["page", {name: $page}]}')
    curl -s -X POST \
         -H "Authorization: Bearer $LOGSEQ_API_TOKEN" \
         -H "Content-Type: application/json" \
         -d "$REQUEST_BODY" \
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
    tmux new-session -d -s "$SESSION_NAME" -c "$TMUX_C_PATH"
fi

# Now, connect to the session in the appropriate way.
if [[ -z "$TMUX" ]]; then
    echo "--> Attaching to tmux session '$SESSION_NAME'..."
    tmux attach-session -t "$SESSION_NAME"
else
    echo "--> Switching to tmux session '$SESSION_NAME'..."
    tmux switch-client -t "$SESSION_NAME"
fi

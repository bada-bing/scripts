#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DOCUMENT_MANAGEMENT_CONFIG:-$SCRIPT_DIR/document_management.env}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

INBOX="${DOCUMENT_INBOX_DIR:-}"
QUEUE_DIR="${DOCUMENT_QUEUE_DIR:-}"
ARRIVAL_LOG="${DOCUMENT_ARRIVAL_LOG:-$QUEUE_DIR/arrivals.log}"
REMINDER_NAME="${DOCUMENT_REMINDER_NAME:-}"
REMINDERS_LIST="${DOCUMENT_REMINDERS_LIST:-Reminders}"
DEBOUNCE_SECONDS="${DOCUMENT_DEBOUNCE_SECONDS:-3}"
PROCESS_SCRIPT="$SCRIPT_DIR/process_inbox.sh"

require_config() {
    local name="$1"
    local value="$2"

    if [ -z "$value" ]; then
        echo "Error: $name is not configured"
        echo "Set it in the environment or in DOCUMENT_MANAGEMENT_CONFIG."
        exit 1
    fi
}

require_config "DOCUMENT_INBOX_DIR" "$INBOX"
require_config "DOCUMENT_QUEUE_DIR" "$QUEUE_DIR"
require_config "DOCUMENT_REMINDER_NAME" "$REMINDER_NAME"
mkdir -p "$INBOX" "$QUEUE_DIR"

# Disable job control messages
set +m

# Log file arrival
log_arrival() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ARRIVAL_LOG"
}

# Function to create/update reminder
create_reminder() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating reminder after debounce period" >> "$ARRIVAL_LOG"
    osascript <<EOF
tell application "Reminders"
    set targetList to list "$REMINDERS_LIST"
    
    set existingReminders to reminders of targetList whose name is "$REMINDER_NAME"
    
    if (count of existingReminders) = 0 then
        make new reminder at end of targetList with properties {name:"$REMINDER_NAME", remind me date:current date}
    else
        set r to item 1 of existingReminders
        if completed of r is true then
            set completed of r to false
            set remind me date of r to current date
        end if
    end if
end tell
EOF
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watcher started. Monitoring: $INBOX" | tee -a "$ARRIVAL_LOG"

# Track pending reminder creation
REMINDER_PID=""

# Watch for new files
fswatch -0 "$INBOX" | while read -d "" filepath; do
    if [[ "$filepath" == *.pdf ]]; then
        if [ -f "$filepath" ]; then
            filename=$(basename "$filepath")
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] New file detected: $filename" | tee -a "$ARRIVAL_LOG"
            
            # Cancel any pending reminder creation (suppress kill output)
            if [ -n "$REMINDER_PID" ] && kill -0 "$REMINDER_PID" 2>/dev/null; then
                kill "$REMINDER_PID" 2>/dev/null
                wait "$REMINDER_PID" 2>/dev/null
            fi
            
            # Schedule new reminder creation after debounce period
            (
                sleep "$DEBOUNCE_SECONDS"
                create_reminder
            ) &
            REMINDER_PID=$!
        fi
    fi
done

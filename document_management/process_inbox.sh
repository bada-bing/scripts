#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DOCUMENT_MANAGEMENT_CONFIG:-$SCRIPT_DIR/document_management.env}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

INBOX_DIR="${DOCUMENT_INBOX_DIR:-}"
QUEUE_DIR="${DOCUMENT_QUEUE_DIR:-}"
FAILED_FILE_LIST="${DOCUMENT_FAILED_FILE_LIST:-$QUEUE_DIR/failed.txt}"
REMINDER_NAME="${DOCUMENT_REMINDER_NAME:-}"
REMINDERS_LIST="${DOCUMENT_REMINDERS_LIST:-Reminders}"
PROCESS_DOCUMENT_SCRIPT="$SCRIPT_DIR/process_document.sh"

require_config() {
    local name="$1"
    local value="$2"

    if [ -z "$value" ]; then
        echo "Error: $name is not configured"
        echo "Set it in the environment or in DOCUMENT_MANAGEMENT_CONFIG."
        exit 1
    fi
}

require_config "DOCUMENT_INBOX_DIR" "$INBOX_DIR"
require_config "DOCUMENT_QUEUE_DIR" "$QUEUE_DIR"
require_config "DOCUMENT_REMINDER_NAME" "$REMINDER_NAME"
mkdir -p "$QUEUE_DIR"

# Generate timestamp for processed files
timestamp() {
    date '+%Y-%m-%d-%H%M%S'
}

# Clear the reminder after successful processing
clear_reminder() {
    osascript <<EOF
tell application "Reminders"
    set targetList to list "$REMINDERS_LIST"
    set existingReminders to reminders of targetList whose name is "$REMINDER_NAME"
    
    if (count of existingReminders) > 0 then
        set r to item 1 of existingReminders
        set completed of r to true
    end if
end tell
EOF
}

echo "Processing files in $INBOX_DIR..."

# Initialize counters
total_files=0
success_count=0
failed_count=0

# Process each file in INBOX
for filepath in "$INBOX_DIR"/*; do
    [ -f "$filepath" ] || continue   # skip if not a file
    
    ((total_files++))
    filename=$(basename "$filepath")

    echo "Processing: $filename"
    
    "$PROCESS_DOCUMENT_SCRIPT" "$filepath"
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "✓ Success: $filename"
        ((success_count++))
    else
        echo "✗ Failed: $filename (exit code: $exit_code)"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $filename (exit code: $exit_code)" >> "$FAILED_FILE_LIST"
        ((failed_count++))
    fi
done

# Print summary
if [ $total_files -eq 0 ]; then
    echo "No files to process."
else
    echo "=========================================="
    echo "Processing complete: $success_count/$total_files succeeded, $failed_count failed"
    echo "=========================================="
    
    # Clear reminder only if all files succeeded
    if [ $failed_count -eq 0 ]; then
        clear_reminder
        echo "Reminder cleared."
    else
        echo "Reminder kept due to failures."
        echo "Check $FAILED_FILE_LIST for details."
    fi
fi

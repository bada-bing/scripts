#!/usr/bin/env bash
# Usage: complete_reminder.sh <reminder_name>
# Marks the first incomplete reminder with the given name as completed.

REMINDER_NAME="${1:?Usage: complete_reminder.sh <reminder_name>}"

osascript <<APPLESCRIPT
tell application "Reminders"
    set matched to (every reminder whose name is "$REMINDER_NAME" and completed is false)
    if (count of matched) > 0 then
        set completed of item 1 of matched to true
        return "Completed: $REMINDER_NAME"
    else
        return "Not found: $REMINDER_NAME"
    end if
end tell
APPLESCRIPT

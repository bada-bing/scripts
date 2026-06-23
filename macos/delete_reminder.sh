#!/usr/bin/env bash
# Usage: delete_reminder.sh <reminder_name>
# Permanently deletes the first reminder with the given name.

REMINDER_NAME="${1:?Usage: delete_reminder.sh <reminder_name>}"

osascript <<APPLESCRIPT
tell application "Reminders"
    set matched to (every reminder whose name is "$REMINDER_NAME")
    if (count of matched) > 0 then
        delete item 1 of matched
        return "Deleted: $REMINDER_NAME"
    else
        return "Not found: $REMINDER_NAME"
    end if
end tell
APPLESCRIPT

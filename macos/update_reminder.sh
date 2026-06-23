#!/usr/bin/env bash
# Usage: update_reminder.sh <reminder_name> <new_date YYYY-MM-DD>
# Updates the due date of the first reminder with the given name.

REMINDER_NAME="${1:?Usage: update_reminder.sh <reminder_name> <new_date YYYY-MM-DD>}"
NEW_DATE="${2:?Usage: update_reminder.sh <reminder_name> <new_date YYYY-MM-DD>}"

YEAR=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%Y")
MONTH=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%-m")
DAY=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%-d")

osascript <<APPLESCRIPT
tell application "Reminders"
    set matched to (every reminder whose name is "$REMINDER_NAME")
    if (count of matched) > 0 then
        set r to item 1 of matched
        set newDate to due date of r
        if newDate is missing value then set newDate to current date
        set year of newDate to $YEAR
        set month of newDate to $MONTH
        set day of newDate to $DAY
        set hours of newDate to 9
        set minutes of newDate to 0
        set seconds of newDate to 0
        set due date of r to newDate
        return "Updated: $REMINDER_NAME → $NEW_DATE"
    else
        return "Not found: $REMINDER_NAME"
    end if
end tell
APPLESCRIPT

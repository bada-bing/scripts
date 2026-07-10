#!/usr/bin/env bash
# Usage: update_reminder.sh <reminder_name> <new_date YYYY-MM-DD> [HH:MM]
# Updates the due date (and optionally time) of the first reminder with the given name.

REMINDER_NAME="${1:?Usage: update_reminder.sh <reminder_name> <new_date YYYY-MM-DD> [HH:MM]}"
NEW_DATE="${2:?Usage: update_reminder.sh <reminder_name> <new_date YYYY-MM-DD> [HH:MM]}"
NEW_TIME="${3:-09:00}"

YEAR=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%Y")
MONTH=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%-m")
DAY=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%-d")
HOUR=$(echo "$NEW_TIME" | cut -d: -f1 | sed 's/^0//')
MINUTE=$(echo "$NEW_TIME" | cut -d: -f2 | sed 's/^0//')

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
        set hours of newDate to $HOUR
        set minutes of newDate to $MINUTE
        set seconds of newDate to 0
        set due date of r to newDate
        return "Updated: $REMINDER_NAME → $NEW_DATE $NEW_TIME"
    else
        return "Not found: $REMINDER_NAME"
    end if
end tell
APPLESCRIPT

#!/usr/bin/env bash
# Usage: create_reminder.sh <name> [date YYYY-MM-DD] [list_name]
# Creates a new reminder. Defaults to no due date and the "Reminders" list.

REMINDER_NAME="${1:?Usage: create_reminder.sh <name> <date YYYY-MM-DD> [list_name]}"
NEW_DATE="${2:?Usage: create_reminder.sh <name> <date YYYY-MM-DD> [list_name]}"
LIST_NAME="${3:-Reminders}"

YEAR=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%Y")
MONTH=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%-m")
DAY=$(date -j -f "%Y-%m-%d" "$NEW_DATE" "+%-d")

osascript <<APPLESCRIPT
tell application "Reminders"
    set targetList to list "$LIST_NAME"
    set r to make new reminder at end of targetList with properties {name:"$REMINDER_NAME"}
    set newDate to current date
    set year of newDate to $YEAR
    set month of newDate to $MONTH
    set day of newDate to $DAY
    set hours of newDate to 9
    set minutes of newDate to 0
    set seconds of newDate to 0
    set due date of r to newDate
    return "Created: $REMINDER_NAME → $NEW_DATE"
end tell
APPLESCRIPT

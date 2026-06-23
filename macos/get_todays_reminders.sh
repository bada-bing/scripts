#!/usr/bin/env bash
# Lists overdue and today's incomplete reminders across all lists.

osascript <<APPLESCRIPT
tell application "Reminders"
    set rightNow to current date
    set startOfToday to rightNow
    set hours of startOfToday to 0
    set minutes of startOfToday to 0
    set seconds of startOfToday to 0
    set endOfToday to startOfToday + (23 * 3600 + 59 * 60 + 59)

    set overdueOutput to ""
    set todayOutput to ""

    repeat with aList in every list
        set listName to name of aList
        repeat with aReminder in (reminders of aList whose completed is false)
            set dueDate to due date of aReminder
            if dueDate is not missing value and dueDate <= endOfToday then
                set dueDateStr to (short date string of dueDate)
                set reminderLine to "  [" & listName & "] " & (name of aReminder) & " — due: " & dueDateStr & linefeed
                if dueDate < startOfToday then
                    set overdueOutput to overdueOutput & reminderLine
                else
                    set todayOutput to todayOutput & reminderLine
                end if
            end if
        end repeat
    end repeat

    if overdueOutput is "" then set overdueOutput to "  (none)" & linefeed
    if todayOutput is "" then set todayOutput to "  (none)" & linefeed

    return "OVERDUE" & linefeed & overdueOutput & linefeed & "TODAY" & linefeed & todayOutput
end tell
APPLESCRIPT

#!/bin/bash

# This script checks the number of unread mails in the Mail app
# It checks all the accounts and mailboxes which contain Inbox in the name

APPLESCRIPT='tell application "Mail"
    set totalUnreadCount to 0
    set accountList to every account
    repeat with eachAccount in accountList
        set mailboxList to every mailbox of eachAccount
        repeat with eachMailbox in mailboxList
            if name of eachMailbox contains "Inbox" then
                set unreadCount to unread count of eachMailbox
                set totalUnreadCount to totalUnreadCount + unreadCount
            end if
        end repeat
    end repeat
    return totalUnreadCount
end tell'

# Execute the AppleScript and get the result
UNREAD_COUNT=$(osascript -e "$APPLESCRIPT")

echo "The number of unread mails: $UNREAD_COUNT"
#!/usr/bin/env python3
"""Nag if a day's manually-captured health metrics are missing from the store.

Some metrics can only come from you (they are never auto-ingested from Hevy or
CleanSlate): whether you fasted, and what training you did. If any of these are
absent from the store for the given date, this creates an URGENT reminder so the
gap is caught the same evening rather than lost.

"Urgent" here means a Reminders *alarm* that fires even when a Focus is on or the
device is muted — the one thing that reliably breaks through in the evening. That
attribute is NOT exposed by the Reminders AppleScript dictionary (which only has
due date / priority / flagged), so it cannot be set via osascript. It CAN be set
by the Shortcuts "New Reminder" action, so creation is delegated to a shortcut
named SHORTCUT_NAME (see below); the title is piped in as the shortcut's input.

Dedup/clear stays on osascript — deleting reminders works fine there.

The shortcut must exist (build once in Shortcuts.app) and do:
  Get Text from Input -> Current Date -> Adjust Date (+5 min, so the reminder
  has time to iCloud-sync to the iPhone before its alarm fires)
  -> New Reminder(title = Text, list = Reminders,
                  Alert = At Time = adjusted date, Urgent = on, Priority = High)

Behaviour:
  - Idempotent: on every run it first removes any prior incomplete reminder for
    this date, then recreates one only if data is still missing. So repeated
    runs never pile up, the "missing:" list stays accurate, and once you have
    logged everything the reminder auto-clears.

Usage: remind_if_incomplete.py [YYYY-MM-DD]   (defaults to today)
"""

import os
import subprocess
import sys
import tempfile
from datetime import datetime

from health_db import connect

# Metrics that only a human can supply — absence means "not logged yet".
REQUIRED_MANUAL = ["fasting", "training"]

REMINDER_LIST = "Reminders"
PREFIX = "⚠️ Log health data for"  # stable per-date prefix used for dedup/clear
SHORTCUT_NAME = "Create Urgent Health Reminder"  # builds the urgent (alarm) reminder


def missing_metrics(date: str) -> list:
    conn = connect()
    present = {m for (m,) in conn.execute(
        "SELECT metric FROM daily_metrics WHERE date = ?", (date,)
    )}
    conn.close()
    return [m for m in REQUIRED_MANUAL if m not in present]


def clear_existing(name_prefix: str) -> None:
    """Best-effort delete of any incomplete reminder for this date (dedup/clear).

    Reminders' AppleScript collection is volatile under iCloud sync, so we
    iterate by index in reverse (a deletion never shifts an item we have yet to
    visit) and guard each access with a try. Failure here is non-fatal: creating
    the nag matters more than perfect dedup, so a hiccup only warns.
    """
    script = f'''tell application "{REMINDER_LIST}"
    set theList to list "{REMINDER_LIST}"
    set n to count of reminders of theList
    repeat with i from n to 1 by -1
        try
            set r to reminder i of theList
            if (completed of r is false) and (name of r starts with "{name_prefix}") then delete r
        end try
    end repeat
end tell'''
    result = subprocess.run(
        ["osascript", "-"], input=script, text=True, capture_output=True,
    )
    if result.returncode != 0:
        print(f"warning: clear step failed (non-fatal): {result.stderr.strip()}", file=sys.stderr)


def create_urgent(title: str) -> None:
    """Create the urgent (alarm) reminder via the Shortcuts action.

    Delegated to a shortcut because the "urgent" alarm is not settable through
    the Reminders AppleScript dictionary. The title is passed as the shortcut's
    input via a temp file (most reliable form for `shortcuts run`).
    """
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(title)
        input_path = f.name
    try:
        result = subprocess.run(
            ["shortcuts", "run", SHORTCUT_NAME, "--input-path", input_path],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"shortcuts run error: {result.stderr.strip()}", file=sys.stderr)
            sys.exit(1)
    finally:
        os.unlink(input_path)


def sync_reminder(date: str, missing: list) -> None:
    name_prefix = f"{PREFIX} {date}"
    clear_existing(name_prefix)
    if missing:
        title = f'{name_prefix} (missing: {", ".join(missing)})'
        create_urgent(title)
        print(f"urgent reminder created: {title}")
    else:
        print("no missing metrics — reminder cleared if any")


def main():
    if len(sys.argv) > 1:
        try:
            target = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: remind_if_incomplete.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        target = datetime.now()

    date = target.strftime("%Y-%m-%d")
    missing = missing_metrics(date)
    if missing:
        print(f"Missing manual metrics for {date}: {', '.join(missing)}")
    else:
        print(f"All manual metrics present for {date}")
    sync_reminder(date, missing)


if __name__ == "__main__":
    main()

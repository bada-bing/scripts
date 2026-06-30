#!/usr/bin/env python3
"""Fetch today's Hevy workout volume and write it to today's Logseq journal."""

import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

HEVY_API_BASE = "https://api.hevyapp.com"
LOGSEQ_JOURNALS = Path.home() / "Documents/Logseq/KB/journals"


def hevy_get(path: str, api_key: str) -> dict:
    url = f"{HEVY_API_BASE}{path}"
    req = urllib.request.Request(url, headers={"api-key": api_key})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def fetch_todays_workouts(api_key: str, today: str) -> list:
    """Fetch workouts started today (YYYY-MM-DD). Stops paging once past today."""
    workouts = []
    page = 1
    while True:
        data = hevy_get(f"/v1/workouts?page={page}&pageSize=10", api_key)
        found_any_today = False
        for w in data["workouts"]:
            start = w.get("start_time", "")
            if start.startswith(today):
                workouts.append(w)
                found_any_today = True
        if not found_any_today or page >= data["page_count"]:
            break
        page += 1
    return workouts


def compute_volume_kg(workouts: list) -> float:
    """Sum weight_kg * reps for all sets across all workouts (matches Hevy mobile app)."""
    total = 0.0
    for w in workouts:
        for ex in w.get("exercises", []):
            for s in ex.get("sets", []):
                weight = s.get("weight_kg") or 0
                reps = s.get("reps") or 0
                total += weight * reps
    return total


def update_journal(journal_path: Path, volume_kg: float) -> None:
    if not journal_path.exists():
        print(f"Journal not found: {journal_path}", file=sys.stderr)
        sys.exit(1)

    lines = journal_path.read_text().splitlines(keepends=True)
    updated = False
    result = []
    for line in lines:
        stripped = line.lstrip()
        item = stripped[2:] if stripped.startswith("- ") else stripped
        if item.startswith("volume_kg::"):
            indent = line[: len(line) - len(stripped)]
            result.append(f"{indent}- volume_kg:: {round(volume_kg)}\n")
            updated = True
        elif item.startswith("training::") and item.strip() == "training::":
            indent = line[: len(line) - len(stripped)]
            result.append(f"{indent}- training:: L\n")
        else:
            result.append(line)

    if not updated:
        print(f"Warning: 'volume_kg::' not found in {journal_path}. Volume: {round(volume_kg)} kg", file=sys.stderr)
        print(f"Add manually: volume_kg:: {round(volume_kg)}")
        return

    journal_path.write_text("".join(result))
    print(f"volume_kg:: {round(volume_kg)} written to {journal_path.name}")


def main():
    api_key = os.environ.get("HEVY_API_KEY")
    if not api_key:
        print("Error: HEVY_API_KEY env var not set", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) > 1:
        try:
            target = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: log_hevy_volume.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        target = datetime.now()

    today = target.strftime("%Y-%m-%d")
    journal_filename = target.strftime("%Y_%m_%d") + ".md"
    journal_path = LOGSEQ_JOURNALS / journal_filename

    try:
        workouts = fetch_todays_workouts(api_key, today)
    except urllib.error.HTTPError as e:
        print(f"Hevy API error {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)

    if not workouts:
        print(f"No Hevy workouts found for {today}")
        return

    volume = compute_volume_kg(workouts)
    print(f"Workouts: {len(workouts)}, Total volume: {round(volume)} kg")
    update_journal(journal_path, volume)


if __name__ == "__main__":
    main()

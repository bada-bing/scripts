#!/usr/bin/env python3
"""Fetch a day's Hevy workout volume and upsert it into the health store."""

import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone

from health_db import connect, get_metrics, refresh_wide_view, upsert_metric

HEVY_API_BASE = "https://api.hevyapp.com"


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


def update_store(date: str, volume_kg: float) -> None:
    conn = connect()
    upsert_metric(conn, date, "volume", str(round(volume_kg)), "hevy")
    # seed training with L only when nothing is logged yet; C/S codes come via the health-inbox
    if not get_metrics(conn, date).get("training"):
        upsert_metric(conn, date, "training", "L", "hevy")
    refresh_wide_view(conn)
    conn.commit()
    conn.close()
    print(f"volume:: {round(volume_kg)} written to health store")


def main():
    api_key = os.environ.get("HEVY_API_KEY")
    if not api_key:
        print("Error: HEVY_API_KEY env var not set", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) > 1:
        try:
            target = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: hevy_to_db.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        target = datetime.now()

    today = target.strftime("%Y-%m-%d")

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
    update_store(today, volume)


if __name__ == "__main__":
    main()

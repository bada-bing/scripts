#!/usr/bin/env python3
"""Fetch a day's CleanSlate calorie total and upsert it into the health store."""

import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

from health_db import connect, refresh_wide_view, upsert_metric

CLEANSLATE_URL = "https://app.cleanslate.sh/auth/graphql"

LOGS_QUERY = """
query($start: timestamptz!, $end: timestamptz!) {
    logs(where: {
        createdAt: {_gte: $start, _lt: $end},
        consumed: {_eq: true}
    }) {
        amount
        unit
        basicFood
        logToFood { name caloriesPerCount caloriesPerGram countToGram tbspToGram }
    }
}
"""

BASIC_FOODS_QUERY = """
query($ids: [String!]!) {
    foods(where: {basicFoodId: {_in: $ids}}) {
        basicFoodId name caloriesPerCount caloriesPerGram countToGram tbspToGram
    }
}
"""


def graphql(token: str, query: str, variables: dict) -> dict:
    payload = {"token": token, "query": query, "variables": variables}
    req = urllib.request.Request(
        CLEANSLATE_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def fetch_logs(token: str, date: str) -> list:
    start = f"{date}T00:00:00+00:00"
    end = f"{(datetime.strptime(date, '%Y-%m-%d') + timedelta(days=1)).strftime('%Y-%m-%d')}T00:00:00+00:00"
    logs = graphql(token, LOGS_QUERY, {"start": start, "end": end})["logs"]

    # Resolve basic food data for logs that reference the built-in food database
    basic_ids = [l["basicFood"] for l in logs if l.get("basicFood") and not l.get("logToFood")]
    if basic_ids:
        foods = graphql(token, BASIC_FOODS_QUERY, {"ids": basic_ids})["foods"]
        food_by_id = {f["basicFoodId"]: f for f in foods}
        for log in logs:
            if log.get("basicFood") and not log.get("logToFood"):
                log["logToFood"] = food_by_id.get(log["basicFood"])

    return logs


def calories_for(amount: float, unit: str, food: dict) -> float:
    if unit == "COUNT":
        if food.get("caloriesPerCount"):
            return amount * food["caloriesPerCount"]
        if food.get("countToGram") and food.get("caloriesPerGram"):
            return amount * food["countToGram"] * food["caloriesPerGram"]
    elif unit == "GRAM":
        return amount * (food.get("caloriesPerGram") or 0)
    elif unit == "TBSP":
        if food.get("tbspToGram") and food.get("caloriesPerGram"):
            return amount * food["tbspToGram"] * food["caloriesPerGram"]
    return 0


def compute_calories(logs: list) -> float:
    total = 0.0
    for log in logs:
        food = log.get("logToFood") or {}
        kcal = calories_for(log["amount"], log["unit"], food)
        if kcal == 0 and not food:
            print(f"Warning: no food data for a log entry — skipped", file=sys.stderr)
        total += kcal
    return total


def update_store(date: str, calories: int) -> None:
    conn = connect()
    upsert_metric(conn, date, "calories", str(calories), "cleanslate")
    refresh_wide_view(conn)
    conn.commit()
    conn.close()
    print(f"calories:: {calories} written to health store")


def main():
    token = os.environ.get("CLEAN_SLATE_API_TOKEN")
    if not token:
        print("Error: CLEAN_SLATE_API_TOKEN env var not set", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) > 1:
        try:
            target = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: cleanslate_to_db.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        target = datetime.now(timezone.utc)

    date = target.strftime("%Y-%m-%d")

    try:
        logs = fetch_logs(token, date)
    except urllib.error.HTTPError as e:
        print(f"CleanSlate API error {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)

    if not logs:
        print(f"No CleanSlate logs found for {date}")
        return

    calories = round(compute_calories(logs))
    print(f"Logs: {len(logs)}, Total calories: {calories}")
    update_store(date, calories)


if __name__ == "__main__":
    main()

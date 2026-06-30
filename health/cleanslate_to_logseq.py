#!/usr/bin/env python3
"""Fetch today's CleanSlate calorie total and write it to today's Logseq journal."""

import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta
from pathlib import Path

CLEANSLATE_URL = "https://app.cleanslate.sh/auth/graphql"
LOGSEQ_JOURNALS = Path.home() / "Documents/Logseq/KB/journals"

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


def update_journal(journal_path: Path, calories: int) -> None:
    if not journal_path.exists():
        print(f"Journal not found: {journal_path}", file=sys.stderr)
        sys.exit(1)

    lines = journal_path.read_text().splitlines(keepends=True)
    updated = False
    result = []
    for line in lines:
        stripped = line.lstrip()
        item = stripped[2:] if stripped.startswith("- ") else stripped
        if item.startswith("calories::"):
            indent = line[: len(line) - len(stripped)]
            result.append(f"{indent}- calories:: {calories}\n")
            updated = True
        else:
            result.append(line)

    if not updated:
        print(f"Warning: 'calories::' not found in {journal_path}. Calories: {calories}", file=sys.stderr)
        print(f"Add manually: calories:: {calories}")
        return

    journal_path.write_text("".join(result))
    print(f"calories:: {calories} written to {journal_path.name}")


def main():
    token = os.environ.get("CLEAN_SLATE_API_TOKEN")
    if not token:
        print("Error: CLEAN_SLATE_API_TOKEN env var not set", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) > 1:
        try:
            target = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: cleanslate_to_logseq.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        target = datetime.now(timezone.utc)

    date = target.strftime("%Y-%m-%d")
    journal_filename = datetime.strptime(date, "%Y-%m-%d").strftime("%Y_%m_%d") + ".md"
    journal_path = LOGSEQ_JOURNALS / journal_filename

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
    update_journal(journal_path, calories)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render the History tables of Health_Dashboard from the health store.

For each goal in health_goals.toml, evaluates adherence over the past N days
and writes a table into the `### History` section (nested under
`## Goals Progress`) of Health_Dashboard.md:
- Daily goals: one row per day — hit, miss, or no data
- Weekly goals: one row per calendar week (Mon–Sun) — hit or miss

Usage: history_to_logseq.py [days]   (defaults to 30)
"""

import sys
import tomllib
from datetime import datetime, timedelta
from pathlib import Path

from goals_eval import evaluate, week_bounds, GOALS_PATH, RULE_RE, OP_FN, NEGATIVE_VALUES
from health_db import connect
from logseq_upsert import upsert_child_section

DASHBOARD_PATH = Path.home() / "Documents/Logseq/KB/pages/Health_Dashboard.md"
PARENT_HEADING = "## Goals Progress"
CHILD_HEADING = "### History"


def evaluate_daily_range(conn, goal: dict, start: str, end: str) -> list:
    match = RULE_RE.match(goal["rule"].strip())
    if not match:
        return []
    metric, op, target_str = match.groups()
    target = float(target_str)

    rows = conn.execute(
        """
        SELECT date, value FROM daily_metrics
        WHERE metric = ? AND date BETWEEN ? AND ?
        ORDER BY date DESC
        """,
        (metric, start, end),
    ).fetchall()
    by_date = {r[0]: float(r[1]) for r in rows}

    results = []
    dt = datetime.strptime(end, "%Y-%m-%d")
    start_dt = datetime.strptime(start, "%Y-%m-%d")
    while dt >= start_dt:
        date = dt.strftime("%Y-%m-%d")
        if date in by_date:
            actual = by_date[date]
            results.append({"date": date, "actual": actual, "target": target, "op": op, "hit": OP_FN[op](actual, target)})
        dt -= timedelta(days=1)
    return results


def evaluate_weekly_range(conn, goal: dict, start: str, end: str) -> list:
    match = RULE_RE.match(goal["rule"].strip())
    if not match:
        return []
    metric, op, target_str = match.groups()
    target = float(target_str)

    end_dt = datetime.strptime(end, "%Y-%m-%d")
    week_start_dt = end_dt - timedelta(days=end_dt.weekday())  # most recent Monday

    start_dt = datetime.strptime(start, "%Y-%m-%d")
    # include the week that contains start_date, even if the week starts before it
    first_week_dt = start_dt - timedelta(days=start_dt.weekday())
    results = []
    while week_start_dt >= first_week_dt:
        week_end_dt = week_start_dt + timedelta(days=6)
        ws = week_start_dt.strftime("%Y-%m-%d")
        we = week_end_dt.strftime("%Y-%m-%d")
        rows = conn.execute(
            """
            SELECT value FROM daily_metrics
            WHERE date BETWEEN ? AND ? AND metric = ?
            """,
            (ws, we, metric),
        ).fetchall()
        actual = float(sum(1 for (v,) in rows if v and v.strip().lower() not in NEGATIVE_VALUES))
        results.append({"week": f"{ws} – {we}", "actual": actual, "target": target, "op": op, "hit": OP_FN[op](actual, target)})
        week_start_dt -= timedelta(weeks=1)
    return results


def render_section(conn, goals: list, start: str, end: str, today: str) -> list:
    lines = [f"\t- {CHILD_HEADING}\n", f"\t  rendered-at:: {today}\n", "\t  background-color:: blue\n"]
    for goal in goals:
        period = goal["period"]
        goal_start = max(start, goal.get("start_date", start))
        if period == "daily":
            rows = evaluate_daily_range(conn, goal, goal_start, end)
            hits = sum(1 for r in rows if r["hit"])
            total = len(rows)
            lines.append(f"\t  **{goal['name']}** — {hits}/{total} days within target\n")
            lines.append("\t  \n")
            lines.append("\t  | Date | Actual | Target | Status |\n")
            lines.append("\t  |---|---|---|---|\n")
            for r in rows:
                status = "✓" if r["hit"] else "✗"
                target = f"{r['op']} {int(r['target'])}"
                lines.append(f"\t  | {r['date']} | {int(r['actual'])} | {target} | {status} |\n")
        elif period == "weekly":
            rows = evaluate_weekly_range(conn, goal, goal_start, end)
            hits = sum(1 for r in rows if r["hit"])
            total = len(rows)
            lines.append(f"\t  **{goal['name']}** — {hits}/{total} weeks at target\n")
            lines.append("\t  \n")
            lines.append("\t  | Week | Actual | Target | Status |\n")
            lines.append("\t  |---|---|---|---|\n")
            for r in rows:
                status = "✓" if r["hit"] else "✗"
                target = f"{r['op']} {int(r['target'])}"
                lines.append(f"\t  | {r['week']} | {int(r['actual'])} | {target} | {status} |\n")
        lines.append("\t  \n")
    return lines


def sync(lookback_days: int) -> None:
    today = datetime.now().strftime("%Y-%m-%d")
    start = (datetime.now() - timedelta(days=lookback_days)).strftime("%Y-%m-%d")

    with open(GOALS_PATH, "rb") as f:
        goals = tomllib.load(f).get("goal", [])

    conn = connect()
    rendered = render_section(conn, goals, start, today, today)
    conn.close()

    text = DASHBOARD_PATH.read_text()
    lines = text.splitlines(keepends=True)

    lines = upsert_child_section(lines, PARENT_HEADING, CHILD_HEADING, rendered)

    new_text = "".join(lines)
    if new_text != text:
        DASHBOARD_PATH.write_text(new_text)

    print(f"Health_Dashboard History synced — {start} to {today}")


def main():
    lookback = 30
    if len(sys.argv) > 1:
        try:
            lookback = int(sys.argv[1])
        except ValueError:
            print("Usage: history_to_logseq.py [days]", file=sys.stderr)
            sys.exit(1)
    sync(lookback)


if __name__ == "__main__":
    main()

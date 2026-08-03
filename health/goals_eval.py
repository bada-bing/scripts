#!/usr/bin/env python3
"""OBSOLETE — superseded by life_sextant (`sxt report`).

Goal evaluation now lives in `sxt` (metrics + reducers + comparators in health.toml). The
sxt-era dashboard renderer gets evaluated goals from `sxt report --json`, not from this module.
Kept only for the legacy `health.db` dashboard path until that is fully retired.

Evaluate health goals against the store.

Reads goals from private/data/health_goals.toml and evaluates each against
the health store. For daily goals, compares the metric value for the given
date. For weekly goals, counts days in the current calendar week (Mon–Sun)
where the metric has a non-empty, non-negative entry (values like "no",
"none", "false", "0" don't count as a hit).

Usage: goals_eval.py [YYYY-MM-DD]   (defaults to today)
"""

import re
import sys
import tomllib
from datetime import datetime, timedelta
from pathlib import Path

from health_db import connect

GOALS_PATH = Path.home() / "Developer/toolbox/private/data/health_goals.toml"

RULE_RE = re.compile(r"^(\w+)\s*(<=|>=|<|>|==)\s*(\d+(?:\.\d+)?)$")

NEGATIVE_VALUES = {"no", "none", "false", "0", ""}

OP_FN = {
    "<=": lambda a, b: a <= b,
    ">=": lambda a, b: a >= b,
    "<":  lambda a, b: a < b,
    ">":  lambda a, b: a > b,
    "==": lambda a, b: a == b,
}


def week_bounds(date: datetime) -> tuple[str, str]:
    monday = date - timedelta(days=date.weekday())
    sunday = monday + timedelta(days=6)
    return monday.strftime("%Y-%m-%d"), sunday.strftime("%Y-%m-%d")


def evaluate(conn, goal: dict, date: str) -> dict:
    match = RULE_RE.match(goal["rule"].strip())
    if not match:
        return {"name": goal["name"], "error": f"unparseable rule: {goal['rule']}"}

    metric, op, target_str = match.groups()
    target = float(target_str)
    period = goal["period"]

    if period == "daily":
        row = conn.execute(
            "SELECT value FROM daily_metrics WHERE date = ? AND metric = ?",
            (date, metric),
        ).fetchone()
        if row is None:
            return {"name": goal["name"], "metric": metric, "period": period,
                    "actual": None, "target": target, "op": op, "hit": None}
        actual = float(row[0])
        return {"name": goal["name"], "metric": metric, "period": period,
                "actual": actual, "target": target, "op": op, "hit": OP_FN[op](actual, target)}

    if period == "weekly":
        dt = datetime.strptime(date, "%Y-%m-%d")
        week_start, week_end = week_bounds(dt)
        rows = conn.execute(
            """
            SELECT value FROM daily_metrics
            WHERE date BETWEEN ? AND ?
              AND metric = ?
            """,
            (week_start, week_end, metric),
        ).fetchall()
        actual = float(sum(1 for (v,) in rows if v and v.strip().lower() not in NEGATIVE_VALUES))
        return {"name": goal["name"], "metric": metric, "period": period,
                "actual": actual, "target": target, "op": op,
                "hit": OP_FN[op](actual, target), "week": f"{week_start} – {week_end}"}

    return {"name": goal["name"], "error": f"unknown period: {period}"}


def main():
    if len(sys.argv) > 1:
        try:
            dt = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: goals_eval.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        dt = datetime.now()
    date = dt.strftime("%Y-%m-%d")

    with open(GOALS_PATH, "rb") as f:
        goals = tomllib.load(f).get("goal", [])

    conn = connect()
    results = [evaluate(conn, g, date) for g in goals]
    conn.close()

    print(f"Health goals — {date}\n")
    for r in results:
        if "error" in r:
            print(f"  ? {r['name']}: ERROR — {r['error']}")
            continue
        status = "✓" if r["hit"] else ("✗" if r["hit"] is False else "–")
        actual = str(int(r["actual"])) if r["actual"] is not None else "no data"
        period_label = r.get("week", r["period"])
        print(f"  {status}  {r['name']}: {actual} {r['op']} {int(r['target'])}  ({period_label})")


if __name__ == "__main__":
    main()

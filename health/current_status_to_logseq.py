#!/usr/bin/env python3
"""Render the Current Status table of Health_Dashboard from the health store.

Evaluates all goals in health_goals.toml against the store for the given date
and writes the results as a table into the `### Current Status` section
(nested under `## Goals Progress`) of Health_Dashboard.md. The section content
is fully replaced on every run — edit goals.toml, not the page.

`rendered-at` is always the actual wall-clock time the script ran (not the
evaluation date), since Current Status is a live snapshot and freshness is
the point.

Usage: current_status_to_logseq.py [YYYY-MM-DD]   (defaults to today)
"""

import sys
import tomllib
from datetime import datetime
from pathlib import Path

from goals_eval import evaluate, GOALS_PATH
from health_db import connect
from logseq_upsert import upsert_child_section

DASHBOARD_PATH = Path.home() / "Documents/Logseq/KB/pages/Health_Dashboard.md"
PARENT_HEADING = "## Goals Progress"
CHILD_HEADING = "### Current Status"


def format_actual(r: dict) -> str:
    if r["actual"] is None:
        return "^^NO DATA^^"
    return str(int(r["actual"]))


def render_section(results: list, rendered_at: str) -> list:
    lines = [f"\t- {CHILD_HEADING}\n", f"\t  rendered-at:: {rendered_at}\n", "\t  background-color:: blue\n"]
    lines.append("\t  | Goal | Actual | Target | Status |\n")
    lines.append("\t  |---|---|---|---|\n")
    for r in results:
        if "error" in r:
            lines.append(f"\t  | {r['name']} | ERROR | | ? {r['error']} |\n")
            continue
        status = "✓" if r["hit"] else ("✗" if r["hit"] is False else "–")
        actual = format_actual(r)
        target = f"{r['op']} {int(r['target'])}"
        lines.append(f"\t  | {r['name']} | {actual} | {target} | {status} |\n")
    return lines


def sync(date: str) -> None:
    with open(GOALS_PATH, "rb") as f:
        goals = tomllib.load(f).get("goal", [])

    conn = connect()
    results = [evaluate(conn, g, date) for g in goals]
    conn.close()

    text = DASHBOARD_PATH.read_text()
    lines = text.splitlines(keepends=True)

    rendered_at = datetime.now().strftime("%Y-%m-%d %H:%M")
    rendered = render_section(results, rendered_at)
    lines = upsert_child_section(lines, PARENT_HEADING, CHILD_HEADING, rendered)

    new_text = "".join(lines)
    if new_text != text:
        DASHBOARD_PATH.write_text(new_text)

    print(f"Health_Dashboard Current Status synced — {len(results)} goal(s) rendered for {date}")
    for r in results:
        if "error" in r:
            print(f"  ? {r['name']}: {r['error']}")
            continue
        status = "✓" if r["hit"] else ("✗" if r["hit"] is False else "–")
        print(f"  {status} {r['name']}: {format_actual(r)} {r['op']} {int(r['target'])}")


def main():
    if len(sys.argv) > 1:
        try:
            dt = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: current_status_to_logseq.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        dt = datetime.now()
    sync(dt.strftime("%Y-%m-%d"))


if __name__ == "__main__":
    main()

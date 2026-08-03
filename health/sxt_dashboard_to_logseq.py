#!/usr/bin/env python3
"""Render the Goals Progress dashboard from life_sextant (`sxt`).

The sxt-era successor to current_status_to_logseq.py + history_to_logseq.py. Instead of
evaluating goals against the legacy health.db, it asks `sxt report --json` for verdicts
(goal evaluation now lives in sxt). Writes the `### Current Status` and `### History`
sections under `## Goals Progress`, fully replacing each on every run — edit sxt's
health.toml, not the page.

`sxt` is invoked with DATA_DIR/ENV_DIR so it resolves the same store + config the scheduled
sync uses. No API tokens needed — `report` only reads the local store.

Usage: sxt_dashboard_to_logseq.py [days]   (history lookback, defaults to 30)
"""

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

from logseq_upsert import upsert_child_section

# Test page for now; switch to Health_Dashboard.md once validated.
DASHBOARD_PATH = Path.home() / "Documents/Logseq/KB/pages/Health_Dashboard_1.md"
PARENT_HEADING = "## Goals Progress"
CURRENT_HEADING = "### Current Status"
HISTORY_HEADING = "### History"

TOOLBOX = Path.home() / "Developer/toolbox"
SXT = shutil.which("sxt") or str(Path.home() / ".local/bin/sxt")


def sxt_env() -> dict:
    env = dict(os.environ)
    env.setdefault("DATA_DIR", str(TOOLBOX / "private/data"))
    env.setdefault("ENV_DIR", str(TOOLBOX / "private/env"))
    return env


def report(date: str) -> list:
    """`sxt report --json --goals --date <date>` → list of verdicts, one per goal.

    Pinned to `--goals` so the renderer keeps getting only verdicts; `report` without a group
    filter now returns all three layers (keys/metrics/goals)."""
    out = subprocess.run(
        [SXT, "report", "--json", "--goals", "--date", date],
        capture_output=True, text=True, env=sxt_env(),
    )
    if out.returncode != 0:
        raise SystemExit(f"sxt report failed for {date}: {out.stderr.strip()}")
    return json.loads(out.stdout)


def label(goal_key: str) -> str:
    """Display name derived from the sxt goal key: calorie_limit → 'Calorie Limit'."""
    return goal_key.replace("_", " ").title()


def target_str(v: dict) -> str:
    return f"{v['comparator']} {int(v['target'])}"


def status_icon(v: dict) -> str:
    if v["value"] is None:
        return "–"
    return "✓" if v["met"] else "✗"


# --- Current Status: today's verdicts ------------------------------------------------------

def render_current(verdicts: list, rendered_at: str) -> list:
    lines = [
        f"\t- {CURRENT_HEADING}\n",
        f"\t  rendered-at:: {rendered_at}\n",
        "\t  background-color:: blue\n",
        "\t  | Goal | Actual | Target | Status |\n",
        "\t  |---|---|---|---|\n",
    ]
    for v in verdicts:
        actual = "^^NO DATA^^" if v["value"] is None else str(int(v["value"]))
        lines.append(f"\t  | {label(v['goal'])} | {actual} | {target_str(v)} | {status_icon(v)} |\n")
    return lines


# --- History: per-day (daily goals) / per-week (weekly goals) ------------------------------

def week_bounds(d: datetime):
    """Monday–Sunday bounds of the week containing d."""
    monday = d - timedelta(days=d.weekday())
    return monday, monday + timedelta(days=6)


def daily_history(cache: dict, goal_key: str, start: datetime, end: datetime) -> list:
    """One row per day in [start, end] that has data for this goal (skip no-data days)."""
    rows = []
    d = end
    while d >= start:
        ds = d.strftime("%Y-%m-%d")
        v = next(x for x in cache[ds] if x["goal"] == goal_key)
        if v["value"] is not None:
            rows.append((ds, int(v["value"]), target_str(v), "✓" if v["met"] else "✗"))
        d -= timedelta(days=1)
    return rows


def weekly_history(cache: dict, goal_key: str, start: datetime, end: datetime) -> list:
    """One row per calendar week (Mon–Sun) overlapping [start, end]."""
    rows = []
    week_start, _ = week_bounds(end)
    first_week_start, _ = week_bounds(start)
    while week_start >= first_week_start:
        week_end = week_start + timedelta(days=6)
        ref = min(week_end, end)  # evaluate the week via a day inside it, not past `end`
        rs = ref.strftime("%Y-%m-%d")
        v = next(x for x in cache[rs] if x["goal"] == goal_key)
        val = int(v["value"]) if v["value"] is not None else 0
        rows.append((
            f"{week_start:%Y-%m-%d} – {week_end:%Y-%m-%d}", val, target_str(v),
            "✓" if v["met"] else "✗",
        ))
        week_start -= timedelta(weeks=1)
    return rows


def render_history(cache: dict, goals: list, start: datetime, end: datetime, rendered_at: str) -> list:
    lines = [
        f"\t- {HISTORY_HEADING}\n",
        f"\t  rendered-at:: {rendered_at}\n",
        "\t  background-color:: blue\n",
    ]
    for g in goals:
        key = g["goal"]
        weekly = g["window"] == "week"
        rows = weekly_history(cache, key, start, end) if weekly else daily_history(cache, key, start, end)
        hits = sum(1 for r in rows if r[3] == "✓")
        unit = "weeks at target" if weekly else "days within target"
        col = "Week" if weekly else "Date"
        lines.append(f"\t  **{label(key)}** — {hits}/{len(rows)} {unit}\n")
        lines.append("\t  \n")
        lines.append(f"\t  | {col} | Actual | Target | Status |\n")
        lines.append("\t  |---|---|---|---|\n")
        for period, actual, tgt, status in rows:
            lines.append(f"\t  | {period} | {actual} | {tgt} | {status} |\n")
        lines.append("\t  \n")
    return lines


def dates_needed(goals: list, start: datetime, end: datetime) -> set:
    """The exact set of days to evaluate: every day for daily goals, one ref day per week."""
    need = set()
    for g in goals:
        if g["window"] == "week":
            ws, _ = week_bounds(end)
            first, _ = week_bounds(start)
            while ws >= first:
                we = ws + timedelta(days=6)
                need.add(min(we, end).strftime("%Y-%m-%d"))
                ws -= timedelta(weeks=1)
        else:
            d = end
            while d >= start:
                need.add(d.strftime("%Y-%m-%d"))
                d -= timedelta(days=1)
    return need


def sync(lookback_days: int) -> None:
    now = datetime.now()
    end = datetime(now.year, now.month, now.day)
    start = end - timedelta(days=lookback_days)
    today = end.strftime("%Y-%m-%d")

    current = report(today)                       # today's verdicts (also the goal list + windows)
    cache = {d: report(d) for d in dates_needed(current, start, end)}
    cache[today] = current

    text = DASHBOARD_PATH.read_text()
    lines = text.splitlines(keepends=True)
    lines = upsert_child_section(lines, PARENT_HEADING, CURRENT_HEADING,
                                 render_current(current, now.strftime("%Y-%m-%d %H:%M")))
    lines = upsert_child_section(lines, PARENT_HEADING, HISTORY_HEADING,
                                 render_history(cache, current, start, end, today))
    new_text = "".join(lines)
    if new_text != text:
        DASHBOARD_PATH.write_text(new_text)

    print(f"{DASHBOARD_PATH.name}: {len(current)} goal(s), history {start:%Y-%m-%d}..{today}")
    for v in current:
        actual = "NO DATA" if v["value"] is None else int(v["value"])
        print(f"  {status_icon(v)} {label(v['goal'])}: {actual} {target_str(v)}")


def main():
    lookback = 30
    if len(sys.argv) > 1:
        try:
            lookback = int(sys.argv[1])
        except ValueError:
            print("Usage: sxt_dashboard_to_logseq.py [days]", file=sys.stderr)
            sys.exit(1)
    sync(lookback)


if __name__ == "__main__":
    main()

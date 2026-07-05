#!/usr/bin/env python3
"""Get health metric(s) from the health store for a given date.

Usage:
  get_health_metric.py [YYYY-MM-DD] [metric]
  get_health_metric.py [metric] [YYYY-MM-DD]

Arguments can be supplied in either order. Date defaults to today.
If no metric is given, all metrics for that date are printed.

Examples:
  get_health_metric.py                        # all metrics for today
  get_health_metric.py calories               # calories for today
  get_health_metric.py 2026-07-04             # all metrics for July 4th
  get_health_metric.py 2026-07-04 fasting     # fasting for July 4th
"""

import sys
from datetime import datetime

from health_db import connect


def parse_args(argv: list) -> tuple:
    date, metric = None, None
    for arg in argv:
        try:
            datetime.strptime(arg, "%Y-%m-%d")
            date = arg
        except ValueError:
            metric = arg
    if date is None:
        date = datetime.now().strftime("%Y-%m-%d")
    return date, metric


def main():
    date, metric = parse_args(sys.argv[1:])
    conn = connect()

    if metric:
        row = conn.execute(
            "SELECT value FROM daily_metrics WHERE date = ? AND metric = ?",
            (date, metric),
        ).fetchone()
        if row is None:
            print(f"No data for {metric} on {date}", file=sys.stderr)
            sys.exit(1)
        print(row[0])
    else:
        rows = conn.execute(
            "SELECT metric, value FROM daily_metrics WHERE date = ? ORDER BY metric",
            (date,),
        ).fetchall()
        if not rows:
            print(f"No data for {date}", file=sys.stderr)
            sys.exit(1)
        for m, v in rows:
            print(f"{m}: {v}")

    conn.close()


if __name__ == "__main__":
    main()

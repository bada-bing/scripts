"""Health store — the central aggregation point for daily health metrics.

SQLite database in long format: one row per (date, metric). Metric names are
data, not schema, so parameters can be added or retired without migrations.
A `daily_wide` view (regenerated on every write to cover all metrics present)
offers a spreadsheet-shaped read: one row per date, one column per metric.

Sources (Hevy, CleanSlate, manual journal edits) upsert into the store;
`db_to_logseq.py` renders the journal `# Health` block from it.
"""

import sqlite3
from pathlib import Path

DB_PATH = Path.home() / "Developer/toolbox/private/data/health.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS daily_metrics (
    date       TEXT NOT NULL,  -- YYYY-MM-DD
    metric     TEXT NOT NULL,
    value      TEXT NOT NULL,
    source     TEXT NOT NULL,  -- hevy | cleanslate | journal
    updated_at TEXT NOT NULL,
    PRIMARY KEY (date, metric)
);
"""


def connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(SCHEMA)
    return conn


def upsert_metric(conn: sqlite3.Connection, date: str, metric: str, value: str, source: str) -> None:
    conn.execute(
        """
        INSERT INTO daily_metrics (date, metric, value, source, updated_at)
        VALUES (?, ?, ?, ?, datetime('now'))
        ON CONFLICT (date, metric) DO UPDATE
        SET value = excluded.value, source = excluded.source, updated_at = excluded.updated_at
        """,
        (date, metric, str(value), source),
    )


def get_metrics(conn: sqlite3.Connection, date: str) -> dict:
    rows = conn.execute("SELECT metric, value FROM daily_metrics WHERE date = ?", (date,))
    return dict(rows.fetchall())


def refresh_wide_view(conn: sqlite3.Connection) -> None:
    metrics = [r[0] for r in conn.execute("SELECT DISTINCT metric FROM daily_metrics ORDER BY metric")]
    conn.execute("DROP VIEW IF EXISTS daily_wide")
    if not metrics:
        return
    columns = ", ".join(
        f"MAX(CASE WHEN metric = '{m}' THEN value END) AS \"{m}\"" for m in metrics
    )
    conn.execute(f"CREATE VIEW daily_wide AS SELECT date, {columns} FROM daily_metrics GROUP BY date")

#!/usr/bin/env python3
"""Render a journal's # Health block from the health store (one-way).

The health store is the single source of truth for the # Health block:
1. Any `health-inbox` block in the journal is consumed first — its properties
   (manual capture: fasting, training type, ...) are upserted into the store
   and the block is removed. An empty inbox stub is left untouched.
2. The # Health section is re-rendered from the store: one property line per
   metric present for that date, overwriting whatever was there.

Usage: db_to_logseq.py [YYYY-MM-DD]   (defaults to today)
"""

import re
import sys
from datetime import datetime
from pathlib import Path

from health_db import connect, get_metrics, refresh_wide_view, upsert_metric

LOGSEQ_JOURNALS = Path.home() / "Documents/Logseq/KB/journals"
PROP_RE = re.compile(r"^([A-Za-z0-9_-]+)::\s*(.*?)\s*$")
IGNORED_PROPS = {"background-color", "collapsed"}  # block styling, not metrics


def _block_content(line: str) -> str:
    stripped = line.strip()
    return stripped[2:] if stripped.startswith("- ") else stripped


def _is_inbox(line: str) -> bool:
    return _block_content(line).lstrip("#").strip() == "health-inbox"


def extract_inbox(lines: list) -> tuple:
    """Consume the first health-inbox block carrying values. Returns (props, lines)."""
    for i, line in enumerate(lines):
        if not _is_inbox(line):
            continue
        props = {}
        end = i + 1
        while end < len(lines):
            stripped = lines[end].strip()
            if lines[end][:1] not in (" ", "\t") or stripped.startswith("- "):
                break
            match = PROP_RE.match(stripped)
            if not match:
                break
            key, value = match.groups()
            if value and key not in IGNORED_PROPS:
                props[key] = value
            end += 1
        if props:
            return props, lines[:i] + lines[end:]
        return {}, lines
    return {}, lines


def find_health_section(lines: list) -> tuple:
    """Return (start, end, collapsed) of the top-level # Health block, or None."""
    start = None
    for i, line in enumerate(lines):
        if _block_content(line) == "# Health" and line[:1] not in (" ", "\t"):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    collapsed = False
    for i in range(start + 1, len(lines)):
        if lines[i][:1] not in (" ", "\t", "\n"):
            end = i
            break
        if lines[i].strip() == "collapsed:: true":
            collapsed = True
    return start, end, collapsed


def render_health_section(metrics: dict, collapsed: bool) -> list:
    lines = ["- # Health\n"]
    if collapsed:
        lines.append("  collapsed:: true\n")
    for i, key in enumerate(sorted(metrics)):
        prefix = "\t- " if i == 0 else "\t  "
        lines.append(f"{prefix}{key}:: {metrics[key]}\n")
    return lines


def sync_journal(date: str) -> None:
    journal_path = LOGSEQ_JOURNALS / (date.replace("-", "_") + ".md")
    if not journal_path.exists():
        print(f"Journal not found: {journal_path}", file=sys.stderr)
        sys.exit(1)

    text = journal_path.read_text()
    lines = text.splitlines(keepends=True)

    inbox, lines = extract_inbox(lines)
    conn = connect()
    for key, value in inbox.items():
        upsert_metric(conn, date, key, value, "journal")
    if inbox:
        refresh_wide_view(conn)
        conn.commit()
    metrics = get_metrics(conn, date)
    conn.close()

    section = find_health_section(lines)
    if section:
        block = render_health_section(metrics, section[2])
        lines = lines[: section[0]] + block + lines[section[1] :]
    elif metrics:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines = lines + render_health_section(metrics, False)

    new_text = "".join(lines)
    if new_text != text:
        journal_path.write_text(new_text)
    print(f"{journal_path.name} synced: " + (", ".join(f"{k}={v}" for k, v in sorted(metrics.items())) or "no data"))


def main():
    if len(sys.argv) > 1:
        try:
            target = datetime.strptime(sys.argv[1], "%Y-%m-%d")
        except ValueError:
            print("Usage: db_to_logseq.py [YYYY-MM-DD]", file=sys.stderr)
            sys.exit(1)
    else:
        target = datetime.now()
    sync_journal(target.strftime("%Y-%m-%d"))


if __name__ == "__main__":
    main()

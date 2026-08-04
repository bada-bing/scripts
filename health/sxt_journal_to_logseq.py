#!/usr/bin/env python3
"""Render a day's journal `# Health` block from life_sextant (`sxt`).

The sxt-era successor to db_to_logseq.py. Instead of the legacy health.db, it asks
`sxt report --json --keys` for the day's recorded values and writes them as
`key:: value` property lines under the journal's `# Health` block. The journal is a
faithful mirror of the store: canonical sxt key names, present values only.

Unlike the old script, this one guarantees the journal exists: a missing-or-empty
`journals/YYYY_MM_DD.md` is first materialized from the Logseq `_DAILY_TEMPLATE_`
(read live from pages/_templates_.md, so editing the template changes new journals),
so a headless run needs no Logseq-app visit.

`sxt` is invoked with DATA_DIR/ENV_DIR so it resolves the same store the scheduled
sync uses. No API tokens needed — `report` only reads the local store.

Usage: sxt_journal_to_logseq.py [YYYY-MM-DD] [--dry-run]   (date defaults to today)
"""

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

LOGSEQ = Path.home() / "Documents/Logseq/KB"
JOURNALS = LOGSEQ / "journals"
TEMPLATES = LOGSEQ / "pages/_templates_.md"
DAILY_TEMPLATE = "_DAILY_TEMPLATE_"

# A bullet whose sole content is a `<…>` cue (e.g. `<Placeholder>`). Emptied on headless
# materialization — the empty bullet stays (still filled by hand), the dead token goes.
PLACEHOLDER_RE = re.compile(r"^(\s*-)\s*<[^>]*>\s*$")

TOOLBOX = Path.home() / "Developer/toolbox"
SXT = shutil.which("sxt") or str(Path.home() / ".local/bin/sxt")


# --- sxt: the day's recorded values -------------------------------------------------------

def sxt_env() -> dict:
    env = dict(os.environ)
    env.setdefault("DATA_DIR", str(TOOLBOX / "private/data"))
    env.setdefault("ENV_DIR", str(TOOLBOX / "private/env"))
    return env


def report_keys(date: str) -> list:
    """`sxt report --json --keys --date <date>` → [{key, values, unit}, ...]."""
    out = subprocess.run(
        [SXT, "report", "--json", "--keys", "--date", date],
        capture_output=True, text=True, env=sxt_env(),
    )
    if out.returncode != 0:
        raise SystemExit(f"sxt report failed for {date}: {out.stderr.strip()}")
    return json.loads(out.stdout)


def render_value(values: list) -> str:
    """Join a key's recorded values into a single property value.

    Snapshots have one value (`266`, `no`); event keys have several
    (`training_session` → `["L","S"]`). Single-char codes concatenate (`LS`),
    otherwise comma-join for readability.
    """
    if len(values) == 1:
        return values[0]
    if all(len(v) == 1 for v in values):
        return "".join(values)
    return ", ".join(values)


def health_props(date: str) -> dict:
    """{key: rendered value} for every key with data on `date` (empty keys dropped)."""
    return {k["key"]: render_value(k["values"]) for k in report_keys(date) if k["values"]}


# --- journal skeleton from the Logseq daily template --------------------------------------

def daily_template_body() -> list:
    """The `_DAILY_TEMPLATE_` children, dedented one level — the journal skeleton.

    Skips the template's own property lines (`template-including-parent::`, `collapsed::`)
    and takes the tab-indented child bullets, dropping one tab so they sit at top level:
    `- # Work\n`, `\t- <Placeholder>\n`, `- # Health\n`.
    """
    lines = TEMPLATES.read_text().splitlines(keepends=True)
    anchor = next(
        (i for i, ln in enumerate(lines) if ln.strip() == f"template:: {DAILY_TEMPLATE}"),
        None,
    )
    if anchor is None:
        raise SystemExit(f"{DAILY_TEMPLATE} not found in {TEMPLATES}")
    i = anchor + 1
    while i < len(lines) and not lines[i].startswith("\t"):  # skip trailing property lines
        i += 1
    body = []
    while i < len(lines) and lines[i].startswith("\t"):
        line = lines[i][1:]  # dedent one tab
        cue = PLACEHOLDER_RE.match(line.rstrip("\n"))
        body.append(cue.group(1) + "\n" if cue else line)  # keep the empty bullet, drop the token
        i += 1
    if not body:
        raise SystemExit(f"{DAILY_TEMPLATE} has no indented body in {TEMPLATES}")
    return body


# --- the # Health block -------------------------------------------------------------------

def _heading(line: str) -> str:
    """A top-level bullet's heading text, tolerating the leading `- ` Logseq may drop."""
    stripped = line.strip()
    return stripped[2:] if stripped.startswith("- ") else stripped


def find_health_block(lines: list):
    """(start, end) of the top-level `# Health` block, or None. `end` is exclusive."""
    start = None
    for i, line in enumerate(lines):
        if not line.startswith((" ", "\t")) and _heading(line) == "# Health":
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if line_has_content(lines[i]) and not lines[i].startswith((" ", "\t")):
            end = i
            break
    return start, end


def line_has_content(line: str) -> bool:
    return line.strip() != ""


def render_health_block(props: dict, header: str) -> list:
    """The `# Health` heading (preserved verbatim) plus one `key:: value` child per prop."""
    lines = [header if header.endswith("\n") else header + "\n"]
    for i, key in enumerate(sorted(props)):
        prefix = "\t- " if i == 0 else "\t  "
        lines.append(f"{prefix}{key}:: {props[key]}\n")
    return lines


# --- sync ---------------------------------------------------------------------------------

def sync_journal(date: str, dry_run: bool) -> None:
    path = JOURNALS / (date.replace("-", "_") + ".md")
    original = path.read_text() if path.exists() else ""
    created = not original.strip()
    base = "".join(daily_template_body()) if created else original
    lines = base.splitlines(keepends=True)

    props = health_props(date)
    block = find_health_block(lines)
    if block:
        start, end = block
        lines = lines[:start] + render_health_block(props, lines[start]) + lines[end:]
    else:  # no heading in an existing journal — append one
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines = lines + render_health_block(props, "- # Health\n")

    new_text = "".join(lines)
    summary = ", ".join(f"{k}={v}" for k, v in sorted(props.items())) or "no data"
    verb = "created" if created else "synced"

    if dry_run:
        print(f"[dry-run] would be {verb} — {path.name}: {summary}")
        b = find_health_block(new_text.splitlines(keepends=True))
        if b:
            sys.stdout.write("".join(new_text.splitlines(keepends=True)[b[0]:b[1]]))
        return

    if new_text != original:
        path.write_text(new_text)
    print(f"{path.name} {verb}: {summary}")


def main():
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    if args:
        try:
            target = datetime.strptime(args[0], "%Y-%m-%d")
        except ValueError:
            print("Usage: sxt_journal_to_logseq.py [YYYY-MM-DD] [--dry-run]", file=sys.stderr)
            sys.exit(1)
    else:
        target = datetime.now()
    sync_journal(target.strftime("%Y-%m-%d"), dry_run)


if __name__ == "__main__":
    main()

"""Find/replace helpers for nested Logseq bullet sections.

A "section" is a bullet heading line plus everything indented under it
(continuation lines and child bullets) until the next bullet at the same
or a shallower tab depth.
"""

import re

BULLET_RE = re.compile(r"^(\t*)- (.*)$")


def find_heading(lines: list, heading: str, depth: int):
    """Return the index of the bullet line matching `heading` at `depth` tabs, or None."""
    for i, line in enumerate(lines):
        match = BULLET_RE.match(line.rstrip("\n"))
        if match and len(match.group(1)) == depth and match.group(2).strip() == heading:
            return i
    return None


def section_end(lines: list, start: int, depth: int) -> int:
    """Return the index right after the section starting at `start` (a `depth`-tab bullet)."""
    for i in range(start + 1, len(lines)):
        match = BULLET_RE.match(lines[i].rstrip("\n"))
        if match and len(match.group(1)) <= depth:
            return i
    return len(lines)


def upsert_child_section(lines: list, parent_heading: str, child_heading: str, child_lines: list) -> list:
    """Replace (or insert) the `child_heading` bullet (depth 1) under `parent_heading` (depth 0).

    `child_lines` must include the child heading bullet line itself plus its
    continuation/content lines, each newline-terminated.
    """
    parent_start = find_heading(lines, parent_heading, 0)
    if parent_start is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        return lines + ["-\n", f"- {parent_heading}\n"] + child_lines

    parent_end = section_end(lines, parent_start, 0)
    relative_start = find_heading(lines[parent_start:parent_end], child_heading, 1)

    if relative_start is not None:
        child_start = parent_start + relative_start
        child_end = min(section_end(lines, child_start, 1), parent_end)
        return lines[:child_start] + child_lines + lines[child_end:]

    return lines[:parent_end] + child_lines + lines[parent_end:]

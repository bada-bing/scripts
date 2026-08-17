#!/usr/bin/env bash

# Log food into CleanSlate through its web UI, one item per invocation.
#
# The UI is driven over CDP with agent-browser, which must already be attached
# to a browser showing app.cleanslate.sh. See private/context/global/
# cleanslate-guide.md for the setup (OAuth login cannot be automated) and for
# the DOM facts this script relies on.
#
# Usage:
#   cs_log.sh <food> <amount> <unit> <meal>
#   cs_log.sh --search <query>     list what a query matches, change nothing
#   cs_log.sh --batch <file>       one "food amount unit meal" per line
#   cs_log.sh --eaten              tick every unticked row on the day
#   cs_log.sh --totals             print the day's logged calories and protein
#
#   --dry-run   fill the form and print the preview, but do not submit
#
# <food> is matched case-insensitively against the search results. A food that
# sits under an expandable parent is addressed as "parent>child":
#
#   cs_log.sh "cheese>Mozzarella" 25 GRAM Lunch
#   cs_log.sh pizza 350 GRAM Lunch
#   cs_log.sh "Knoppers Peanut Bar" 2 SERVING Snack
#
# An ambiguous <food> is never guessed at: the candidates are printed and the
# script exits 2 without touching the form.

set -euo pipefail

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

die() { echo "cs_log.sh: $1" >&2; exit 1; }

# agent-browser eval prints its result as JSON. Every snippet here returns a
# string, so one json.loads gives back the plain text (newlines included).
# Each snippet is wrapped in an IIFE because evals share a single scope: a bare
# `const` would make the *next* call fail on a redeclaration.
ab() {
  agent-browser eval "(() => { $1 })()" \
    | python3 -c 'import sys, json; s = sys.stdin.read().strip(); print(json.loads(s) if s else "")'
}

# Interpolating a food name into a JS snippet needs it quoted as a JS string
# literal. macOS ships bash 3.2, so ${var@Q} is unavailable and json.dumps does
# the escaping instead.
jsq() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Poll a JS predicate until it returns "yes". Fixed sleeps are unreliable here:
# the result list and the add form both arrive on their own schedule.
wait_for_js() {
  local snippet="$1" tries="${2:-15}"
  for ((i = 0; i < tries; i++)); do
    [[ "$(ab "$snippet")" == "yes" ]] && return 0
    sleep 0.4
  done
  return 1
}

# ── page vocabulary ───────────────────────────────────────────────────────────

# A result button carries a nested <img alt="Food">; a variant button (revealed
# after expanding a parent) is plain text. Both are matched on their trimmed
# label with the "Expand" and "Custom food" suffixes stripped, which is what the
# accessible name glues on.
readonly JS_LABELS='
  const norm = (s) => s.trim()
    .replace(/Custom food$/, "").replace(/Expand$/, "").trim();
  const buttons = () => [...document.querySelectorAll("button")]
    .filter((b) => b.textContent.trim() && !b.querySelector("img[alt=\"Magnifying glass\"]"));
'

# Like the Check button, Back carries no text — its accessible name comes from a
# nested <img alt="Back">, so matching on textContent never finds it.
click_back() {
  ab 'const back = [...document.querySelectorAll("button")]
        .find((b) => b.querySelector("img[alt=\"Back\"]")
                  || b.textContent.trim() === "Back");
      if (!back) return "none";
      back.click();
      return "ok";'
}

# Back out of a form or an expanded group left over from a failed or dry run.
# One click per eval, with a pause: two clicks in a single tick both resolve
# against the pre-render DOM, so the second hits a detached node.
close_overlays() {
  local i
  for i in 1 2 3; do
    [[ "$(click_back)" == "none" ]] && return 0
    sleep 0.5
  done
}

# Clicking the nav button toggles the panel, so an already-open panel must not
# be clicked again.
open_search() {
  close_overlays
  ab 'if (document.querySelector("input[placeholder=\"Search for items...\"]")) return "already open";
      const nav = [...document.querySelectorAll("button")]
        .find((b) => b.querySelector("img[alt=\"Magnifying glass\"]"));
      if (!nav) return "no search button — is CleanSlate the active tab?";
      nav.click();
      return "ok";' >/dev/null
  wait_for_js 'return document.querySelector("input[placeholder=\"Search for items...\"]") ? "yes" : "no"' \
    || die "search panel did not open"
}

# Type into the search box and wait for the result list to settle.
search() {
  agent-browser fill "input[placeholder='Search for items...']" "$1" >/dev/null
  wait_for_js "$JS_LABELS
    const box = document.querySelector('input[placeholder=\"Search for items...\"]');
    if (!box) return 'no';
    return buttons().some((b) => b.compareDocumentPosition(box) & Node.DOCUMENT_POSITION_PRECEDING)
      ? 'yes' : 'no'" || return 1
}

# An expandable group is shown with a trailing ">", mirroring the "parent>child"
# addressing, so a listing says which entries need a second step.
candidates() {
  ab "$JS_LABELS
    const box = document.querySelector('input[placeholder=\"Search for items...\"]');
    const after = (b) => !box
      || (b.compareDocumentPosition(box) & Node.DOCUMENT_POSITION_PRECEDING);
    return buttons().filter(after).map((b) => {
      const raw = b.textContent.trim();
      if (raw.endsWith('Expand')) return norm(raw) + '>';
      if (raw.endsWith('Custom food')) return norm(raw) + '  (custom)';
      return norm(raw);
    }).join('\n');"
}

# Click the one candidate matching $1. Exact (case-insensitive) match wins; a
# unique substring match is accepted; anything else is reported, not guessed.
click_label() {
  ab "$JS_LABELS
    const want = $(jsq "$1").toLowerCase();
    const all = buttons();
    let hits = all.filter((b) => norm(b.textContent).toLowerCase() === want);
    if (!hits.length) {
      hits = all.filter((b) => norm(b.textContent).toLowerCase().includes(want));
    }
    if (!hits.length) return 'MISS';
    if (hits.length > 1) {
      return 'AMBIGUOUS: ' + hits.map((b) => norm(b.textContent)).join(', ');
    }
    hits[0].click();
    return 'ok';"
}

form_food() {
  ab 'const f = document.querySelector("form");
      return f ? f.innerText.split("\n")[0].trim() : "";'
}

# The unit labels render uppercase but the DOM text is lowercase — the casing
# comes from CSS — so the match has to be case-insensitive. The meal defaults to
# whatever suits the current hour, so it always needs an explicit click.
fill_form() {
  local amount="$1" unit="$2" meal="$3"
  agent-browser fill "input[placeholder='Enter amount...']" "$amount" >/dev/null
  ab "const f = document.querySelector('form');
      if (!f) return 'no form';
      const pick = (label) => [...f.querySelectorAll('button')]
        .find((b) => b.textContent.trim().toLowerCase() === label.toLowerCase());
      const u = pick($(jsq "$unit")), m = pick($(jsq "$meal"));
      if (!u) return 'no such unit: ' + $(jsq "$unit");
      if (!m) return 'no such meal: ' + $(jsq "$meal");
      u.click(); m.click();
      return 'ok';"
}

selected_meal() {
  ab 'const f = document.querySelector("form");
      if (!f) return "";
      const m = [...f.querySelectorAll("button.tab")]
        .find((b) => b.className.includes("active"));
      return m ? m.textContent.trim() : "";'
}

preview() {
  ab 'const f = document.querySelector("form");
      if (!f) return "";
      const kcal = f.innerText.match(/Calories:\s*(\d+)/);
      const prot = f.innerText.match(/Protein:\s*(\d+)/);
      return kcal && prot ? kcal[1] + " kcal, " + prot[1] + " g protein" : "";'
}

totals() {
  ab 'const t = document.body.innerText.match(/(\d+)\s*\/\s*\d+[\s\S]*?(\d+)\s*\/\s*\d+/);
      return t ? t[1] + " kcal, " + t[2] + " g protein" : "unavailable";'
}

row_count() {
  ab 'return String(document.querySelectorAll("input[type=checkbox]").length);'
}

# The form closes before the day's list and header totals refresh, so waiting on
# the form alone reports success while a following --totals still reads the old
# figure. Waiting for a new row makes the add verified rather than assumed.
submit() {
  local before="$1"
  agent-browser click "form button:has(img[alt='Check'])" >/dev/null
  wait_for_js 'return document.querySelector("form") ? "no" : "yes"' \
    || die "form did not close — the entry may not have been saved"
  wait_for_js "return document.querySelectorAll('input[type=checkbox]').length > $before ? 'yes' : 'no'" \
    || die "the day's list did not gain a row — the entry may not have been saved"
}

# Every row's checkbox is ticked, so no row needs identifying — which is the one
# case where walking the checkboxes wholesale is safe. Ticking one re-renders the
# list, so the unticked one is re-found on each pass rather than held onto.
mark_eaten() {
  local before
  before="$(ab 'return String([...document.querySelectorAll("input[type=checkbox]")]
                  .filter((c) => !c.checked).length);')"
  for ((i = 0; i < before; i++)); do
    ab 'const cb = [...document.querySelectorAll("input[type=checkbox]")]
          .find((c) => !c.checked);
        if (!cb) return "done";
        cb.click();
        return "ok";' >/dev/null
    sleep 1
  done
  local left
  left="$(ab 'return String([...document.querySelectorAll("input[type=checkbox]")]
                .filter((c) => !c.checked).length);')"
  echo "eaten: ${before} ticked, ${left} still unticked"
  [[ "$left" == "0" ]]
}

# ── one item, end to end ──────────────────────────────────────────────────────

log_item() {
  local food="$1" amount="$2" unit="$3" meal="$4"
  local parent="" child="$food"
  if [[ "$food" == *">"* ]]; then
    parent="${food%%>*}"
    child="${food#*>}"
  fi

  local rows_before
  rows_before="$(row_count)"

  open_search
  search "${parent:-$child}" || die "no results for '${parent:-$child}'"

  local result
  if [[ -n "$parent" ]]; then
    result="$(click_label "$parent")"
    [[ "$result" == "ok" ]] || die "parent '$parent': $result"
    wait_for_js "return document.querySelector('input[placeholder=\"Search for items...\"]') ? 'no' : 'yes'" \
      || die "'$parent' did not expand — is it an expandable group?"
  fi

  result="$(click_label "$child")"
  if [[ "$result" != "ok" ]]; then
    echo "cs_log.sh: could not resolve '$child' ($result). Candidates:" >&2
    candidates | sed 's/^/  /' >&2
    exit 2
  fi

  # A group clicked as if it were a leaf expands instead of opening the form.
  if ! wait_for_js 'return document.querySelector("form") ? "yes" : "no"'; then
    if [[ -z "$parent" ]]; then
      echo "cs_log.sh: '$child' is an expandable group — address it as '$child>variant'." >&2
      echo "Variants:" >&2
      candidates | sed 's/^/  /' >&2
      close_overlays
      exit 2
    fi
    die "add form did not open for '$child'"
  fi

  local opened
  opened="$(form_food)"
  result="$(fill_form "$amount" "$unit" "$meal")"
  [[ "$result" == "ok" ]] || die "$opened: $result"

  local got_meal
  got_meal="$(selected_meal)"
  [[ "$got_meal" == "$meal" ]] || die "meal is '$got_meal', expected '$meal'"

  local p
  p="$(preview)"
  if $dry_run; then
    echo "would log  ${opened} ${amount} $(lower "$unit") → ${meal}${p:+  (${p})}  [dry run]"
    close_overlays
    return 0
  fi

  submit "$rows_before"
  echo "logged  ${opened} ${amount} $(lower "$unit") → ${meal}${p:+  (${p})}"
}

# ── entry point ───────────────────────────────────────────────────────────────

command -v agent-browser >/dev/null || die "agent-browser is not installed"

case "${1:-}" in
  --search)
    [[ $# -eq 2 ]] || die "usage: cs_log.sh --search <query>"
    open_search
    search "$2" || die "no results for '$2'"
    candidates
    ;;
  --eaten)
    mark_eaten
    ;;
  --totals)
    totals
    ;;
  --batch)
    [[ -f "${2:-}" ]] || die "usage: cs_log.sh --batch <file>"
    # The last three fields are amount, unit and meal; everything before them is
    # the food, so multi-word names need no quoting. Read on fd 3 so a
    # subprocess cannot swallow the rest of the file from stdin.
    line_no=0
    while IFS= read -r line <&3 || [[ -n "$line" ]]; do
      line_no=$((line_no + 1))
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" || "$line" == \#* ]] && continue

      meal="${line##* }"; rest="${line% *}"
      unit="${rest##* }"; rest="${rest% *}"
      amount="${rest##* }"; food="${rest% *}"
      [[ "$food" != "$rest" && -n "$food" ]] \
        || die "line $line_no: expected '<food> <amount> <unit> <meal>', got '$line'"
      food="${food%\"}"; food="${food#\"}"

      log_item "$food" "$amount" "$unit" "$meal"
    done 3< "$2"
    echo "day total: $(totals)"
    ;;
  "" | -h | --help)
    sed -n '3,29p' "$0" | sed 's|^# \{0,1\}||'
    ;;
  *)
    [[ $# -eq 4 ]] || die "usage: cs_log.sh <food> <amount> <unit> <meal>"
    log_item "$1" "$2" "$3" "$4"
    ;;
esac

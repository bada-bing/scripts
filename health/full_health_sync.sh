#!/usr/bin/env bash
#
# Full health sync routine — the single entry point that runs the whole loop:
#   1. hevy_to_db.py           ingest training volume from Hevy
#   2. cleanslate_to_db.py     ingest calories from CleanSlate
#   3. db_to_logseq.py         consume health-inbox + render journal # Health block
#   4. current_status_to_logseq.py   refresh Health_Dashboard "Current Status"
#   5. history_to_logseq.py          refresh Health_Dashboard "History"
#
# Designed for unattended (launchd) execution as well as manual use:
#   - Each step runs independently. A failure in one step (e.g. an ingest source
#     is offline) is logged but does NOT abort the remaining steps.
#   - db_to_logseq is skipped when the day's journal does not exist yet — the
#     store still receives the ingested data; the journal render just defers.
#   - Every run is appended to $LOG_FILE with per-step OK/FAIL/SKIP status.
#
# Usage: sync_all.sh [YYYY-MM-DD]   (defaults to today)

set -uo pipefail

TOOLBOX_DIR="${TOOLBOX_DIR:-$HOME/Developer/toolbox}"
HEALTH_DIR="$TOOLBOX_DIR/scripts/health"
LOG_FILE="$TOOLBOX_DIR/private/data/health_sync.log"
JOURNALS_DIR="$HOME/Documents/Logseq/KB/journals"
MISE_BIN="/opt/homebrew/bin/mise"

# launchd runs with a minimal PATH (/usr/bin:/bin), so a bare `python3` resolves
# to system Python 3.9 — which lacks `tomllib` (stdlib only in 3.11+) and breaks
# the dashboard scripts. mise does not manage python, so it just passes `python3`
# through from PATH; putting Homebrew first makes that the 3.11+ interpreter.
export PATH="/opt/homebrew/bin:$PATH"

DATE="${1:-$(date +%F)}"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

# run_step LABEL CMD...  — run a step, capture its output to the log, never abort.
run_step() {
  local label="$1"; shift
  local rc=0
  "$@" >>"$LOG_FILE" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    log "OK   $label"
  else
    log "FAIL $label (exit $rc)"
  fi
}

py() { "$MISE_BIN" exec -- python3 "$HEALTH_DIR/$1" "${@:2}"; }

log "==== health sync start ($DATE) ===="

run_step "hevy_to_db"       py hevy_to_db.py "$DATE"
run_step "cleanslate_to_db" py cleanslate_to_db.py "$DATE"

journal_file="$JOURNALS_DIR/${DATE//-/_}.md"
if [ -f "$journal_file" ]; then
  run_step "db_to_logseq" py db_to_logseq.py "$DATE"
else
  log "SKIP db_to_logseq (no journal: $journal_file)"
fi

run_step "current_status_to_logseq" py current_status_to_logseq.py "$DATE"
run_step "history_to_logseq"         py history_to_logseq.py

# After everything is ingested, nag (urgent reminder) if manual metrics are
# still missing for the day — and auto-clear the nag once they are present.
run_step "remind_if_incomplete" py remind_if_incomplete.py "$DATE"

log "==== health sync end ($DATE) ===="

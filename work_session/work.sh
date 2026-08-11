#!/usr/bin/env bash
#
# The command-line front door to record_work.sh. With no verb it picks a task and
# starts working on it, which is the common case; anything else is handed
# straight through.
#
# Selection lives here rather than in record_work.sh, which takes a key and never
# asks a question.
#
# Usage:
#   fcs.sh [--dry-run]                 pick a task, then start it
#   fcs.sh <task-key> [--dry-run]      start that one without the picker
#   fcs.sh start <task-key> | stop [--later|--done] | status

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<'USAGE'
Usage:
  fcs                         pick a task, then start working on it
  fcs <task-key>              start that one, skipping the picker
  fcs start <task-key>        the same, said explicitly
  fcs stop [--later|--done]   close the interval and mark today's journal
  fcs status                  active task, its journal marker, its session

--dry-run works throughout: it applies nothing and prints what it would do.
A verb is handed to record_work.sh unchanged.
USAGE
}

case "${1:-}" in
    -h|--help)         usage; exit 0 ;;
    start|stop|status) exec "$SCRIPT_DIR/record_work.sh" "$@" ;;
    ""|-*)             ;;  # nothing but flags: pick something
    *)                 exec "$SCRIPT_DIR/record_work.sh" start "$@" ;;
esac

selection=$("$SCRIPT_DIR/select_work.sh" --tasks) || exit 1
[[ -z "$selection" ]] && exit 0

IFS=$'\t' read -r _ key <<< "$selection"
[[ -z "$key" ]] && exit 0

exec "$SCRIPT_DIR/record_work.sh" start "$key" "$@"

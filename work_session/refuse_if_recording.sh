#!/usr/bin/env bash
#
# Exits 0 when nothing is being recorded, and refuses with an explanation when
# something is.
#
# Any open interval refuses a start, including one for the key about to be started.
# An interval forgotten about is invisible if restarting quietly succeeds, and it
# keeps accruing: a sitting meant to be two hours becomes six. So the elapsed time
# is reported, because noticing it is the point.
#
# This is the one definition of that refusal, so the picker can decline before it
# asks a question rather than after - being offered a choice that cannot be acted
# on is worse than being told no.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

[[ "$(timew get dom.active 2>/dev/null || true)" == "1" ]] || exit 0

label=$("$SCRIPT_DIR/get_active_identity.sh" | cut -f2)
elapsed=$(timew get dom.active.duration 2>/dev/null || true)

if [[ -n "${label:-}" ]]; then
    printf "Error: '%s' is already being recorded%s - stop it first\n" \
        "$label" "${elapsed:+ (${elapsed})}" >&2
else
    printf 'Error: an interval with no identity is already being recorded%s\n' \
        "${elapsed:+ (${elapsed})}" >&2
    echo "  stop it first, or label it: timew annotate @1 '<what it was>'" >&2
fi

exit 1

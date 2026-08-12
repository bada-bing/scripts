#!/usr/bin/env bash
#
# Prints the identity of the interval being recorded right now, or nothing when
# no interval is open.
#
# The identity is the tag marked with a "%" prefix - what makes two intervals the
# same piece of work. A bare key is still accepted by its shape, since intervals
# written before the prefix existed carry that form until the backfill.
#
# An interval with no identity prints nothing, which is deliberately the same
# answer as no interval at all: a caller that needs to tell those apart reads
# dom.active itself. This is the one definition of the identity, so record_work.sh
# and the status bar cannot disagree about what is being recorded.
#
# dom.active.json is an error rather than an empty answer when nothing is
# running, so the flag is tested first.

set -uo pipefail

[[ "$(timew get dom.active 2>/dev/null || true)" == "1" ]] || exit 0

timew get dom.active.json 2>/dev/null | jq -r '
    ([.tags[]? | select(startswith("%"))] | first) as $identity
  | if $identity then ($identity | ltrimstr("%"))
    else ([.tags[]? | select(test("^[A-Za-z0-9]+[-_][0-9]+$"))] | first // empty)
    end'

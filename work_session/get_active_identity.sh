#!/usr/bin/env bash
#
# Prints the identity of the interval being recorded right now, or nothing when
# no interval is open.
#
# The identity is the tag marked with a "%" prefix - what makes two intervals the
# same piece of work - and nothing else.
#
# The prefix is dropped by slicing rather than with ltrimstr, which raises on a
# null input in jq 1.8.
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
    [.tags[]? | select(startswith("%"))] | first
  | if . then .[1:] else empty end'

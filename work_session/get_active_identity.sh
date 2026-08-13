#!/usr/bin/env bash
#
# Prints what is being recorded right now as "<kind>\t<identity>", or nothing at
# all when no interval is open or the open one has no identity.
#
# The identity is what makes two intervals the same piece of work. For task work
# it is the tag marked with a "%" prefix; for an adhoc it is the annotation, since
# an adhoc carries no tags. The kind follows from the sigil rather than from a
# stored tag, so nothing has to be kept in step.
#
# An interval with neither prints nothing - the same answer as no interval at all.
# A caller needing to tell those apart reads dom.active itself.
#
# This is the one definition of the identity, so record_work.sh and the status bar
# cannot disagree about what is being recorded.
#
# dom.active.json is an error rather than an empty answer when nothing is running,
# so the flag is tested first. The prefix is dropped by slicing rather than with
# ltrimstr, which raises on a null input in jq 1.8.

set -uo pipefail

[[ "$(timew get dom.active 2>/dev/null || true)" == "1" ]] || exit 0

timew get dom.active.json 2>/dev/null | jq -r '
    ([.tags[]? | select(startswith("%"))] | first) as $tag
  | if $tag then "task\t" + ($tag | .[1:])
    elif (.annotation // "") != "" then "adhoc\t" + .annotation
    else empty
    end'

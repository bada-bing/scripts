#!/usr/bin/env bash
#
# agent_session - the one writer of the agent session store.
#
# A session is one transcript, identified by the agent's own id; resuming it is
# another run of the same session. The store holds what no agent keeps: which
# topic the session served, a task's key, its title and a note on what it did.
# Everything else is derived from the transcript on demand.
#
# One SQLite file, one table, sessions, keyed by agent and id:
#
#   agent       which agent ran it - claude, pi
#   id          the agent's own session id
#   directory   where it ran
#   entrypoint  how it was started - cli, sdk-cli
#   topic       a task's key, or empty for a session with no task
#   title       the session's name, the tmux address while the hook sets it
#   note        one line on what the session did, set by hand
#
# The command reads no tmux and no environment but the store's location: it
# takes everything as arguments, so it runs without any agent, to test or to
# correct a link, and the hook is one caller of it.
#
# Usage:
#   agent_session.sh get   <agent> <id>      the record, as JSON
#   agent_session.sh list  <key>             a topic's sessions, one-shots summed up
#   agent_session.sh list  <key> --one-shots the one-shots, as rows
#   agent_session.sh write < record.json     the whole record, replaced or created
#
# get and write share one shape, an object with the seven keys above, so a
# record is corrected in a pipe:
#
#   agent_session.sh get claude <id> | jq '.note = "..."' | agent_session.sh write
#
# list prints one line per session, tab-separated: started, last used, agent,
# id, title, and the note or, without one, the first prompt. The times are
# read off the transcript, so a session whose transcript is gone shows none.
# One-shots close the listing as one line, "12 one-shots, 14:02 to 16:40".
#
# The store is created on first use, so nothing has to be set up by hand.

set -uo pipefail

DATA_DIR="${DATA_DIR:-$HOME/Developer/toolbox/private/data}"
STORE="${AGENT_SESSION_STORE:-$DATA_DIR/agent_session/sessions.db}"

SCHEMA="
CREATE TABLE IF NOT EXISTS sessions (
    agent      TEXT NOT NULL,
    id         TEXT NOT NULL,
    directory  TEXT NOT NULL,
    entrypoint TEXT NOT NULL,
    topic      TEXT NOT NULL DEFAULT '',
    title      TEXT NOT NULL DEFAULT '',
    note       TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (agent, id)
) STRICT;
"

# Runs SQL against the store, creating the file and the table when either is
# missing. Every verb goes through here, so the schema is applied exactly once
# per call and nowhere else.
query() {
    mkdir -p "$(dirname "$STORE")" || return 1
    sqlite3 "$STORE" "$SCHEMA" "$@"
}

verb="${1:-}"
shift || true

# Quotes a value for SQL: the one place a field is interpolated.
sql() { local q="'"; printf "'%s'" "${1//$q/$q$q}"; }

# Where an agent keeps a session's transcript, from the record alone. Claude
# Code files it under the directory it ran in, every character outside
# [A-Za-z0-9] written as a dash; pi under its own encoding of the directory,
# which the id's suffix finds without reproducing. Prints nothing when the
# transcript is gone, which is the case the store exists for.
transcript() {
    local agent="$1" directory="$2" id="$3" path
    case "$agent" in
        claude) path="$HOME/.claude/projects/$(printf '%s' "$directory" | sed 's/[^A-Za-z0-9]/-/g')/$id.jsonl" ;;
        pi)     path=$(ls "$HOME/.pi/agent/sessions"/*/*"_$id.jsonl" 2>/dev/null | head -1) ;;
        *)      return ;;
    esac
    [[ -f "$path" ]] && printf '%s' "$path"
}

# What list shows per session, read off the transcript: when it started, when
# it was last used, and its first prompt, one line of it. The timestamps are
# the first and the last in the file, which is what started and last used
# mean for a session that is resumed. Both agents stamp every entry and keep
# the user's text as a string or in text blocks, so one reading serves both.
transcript_facts() {
    local path="$1" first last prompt
    first=$(grep -m1 -o '"timestamp":"[^"]*"' "$path" | cut -d'"' -f4)
    last=$(tail -n 20 "$path" | grep -o '"timestamp":"[^"]*"' | tail -1 | cut -d'"' -f4)
    prompt=$(grep -m1 '"role":"user"' "$path" | jq -r '
        .message.content
        | if type == "string" then . else map(select(.type == "text") | .text) | join(" ") end
    ' 2>/dev/null | sed 's/<[^>]*>/ /g' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//' | cut -c1-80)
    printf '%s\t%s\t%s' "$(local_time "$first")" "$(local_time "$last")" "$prompt"
}

# An ISO timestamp from a transcript, UTC, as local YYYY-MM-DD HH:MM.
local_time() {
    [[ -z "$1" ]] && { printf -- '-'; return; }
    date -r "$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${1%%.*}" +%s)" '+%Y-%m-%d %H:%M' 2>/dev/null || printf -- '-'
}

case "$verb" in
    get)
        if [[ $# -ne 2 ]]; then
            echo "Usage: $(basename "$0") get <agent> <id>" >&2
            exit 1
        fi
        record=$(query -json "SELECT agent, id, directory, entrypoint, topic, title, note
                              FROM sessions WHERE agent = $(sql "$1") AND id = $(sql "$2");") \
            || exit 1
        if [[ -z "$record" ]]; then
            echo "Error: no record for $1 $2" >&2
            exit 1
        fi
        jq '.[0]' <<<"$record"
        ;;
    list)
        if [[ $# -lt 1 || $# -gt 2 || ( $# -eq 2 && "$2" != "--one-shots" ) ]]; then
            echo "Usage: $(basename "$0") list <key> [--one-shots]" >&2
            exit 1
        fi
        key="$1"
        # One line per session: started, last used, agent, id, title, and the
        # note when there is one, else the first prompt, else that the
        # transcript is gone. Fields come out on the unit separator rather
        # than a tab: a tab is whitespace to read, which folds two of them
        # into one and drops an empty column, so an empty title would take
        # the note's place.
        rows() {
            query -separator $'\x1f' "SELECT agent, id, directory, title, note FROM sessions
                                      WHERE topic = $(sql "$key") AND entrypoint $1 'sdk-cli'
                                      ORDER BY rowid;" \
                | while IFS=$'\x1f' read -r agent id directory title note; do
                    path=$(transcript "$agent" "$directory" "$id")
                    started='-' used='-' prompt=''
                    [[ -n "$path" ]] && IFS=$'\t' read -r started used prompt < <(transcript_facts "$path")
                    about="${note:-${prompt:-(transcript gone)}}"
                    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$started" "$used" "$agent" "$id" "$title" "$about"
                done | sort
        }
        # One-shots, started as sdk-cli, are not sessions to resume or to
        # build on, so they close the listing as one line, a count and the
        # span of their activity, and are listed as rows only on request.
        if [[ "${2:-}" == "--one-shots" ]]; then
            rows "="
        else
            rows "!="
            rows "=" | awk -F'\t' '
                { n++ }
                $1 != "-" { if (!from || $1 < from) from = $1; if ($2 > to) to = $2 }
                END {
                    if (!n) exit
                    line = n " one-shot" (n == 1 ? "" : "s")
                    if (from) {
                        if (substr(from, 1, 10) == substr(to, 1, 10)) to = substr(to, 12)
                        line = line ", " from " to " to
                    }
                    print line
                }'
        fi
        ;;
    write)
        if [[ $# -ne 0 ]]; then
            echo "Usage: $(basename "$0") write < record.json" >&2
            exit 1
        fi
        input=$(cat)
        if [[ -z "$input" ]]; then
            echo "Error: no record on stdin" >&2
            exit 1
        fi
        # The record comes in as the object get prints, so the two round-trip:
        # get, change a field with jq, write. Unknown keys are refused rather
        # than dropped, since a misspelt key would otherwise erase the field
        # it was meant to set. Absent optional keys read as empty.
        record=$(jq -c '
            . as $r
            | (keys - ["agent", "id", "directory", "entrypoint", "topic", "title", "note"]) as $unknown
            | if $unknown != [] then error("unknown key: " + ($unknown | join(", "))) else . end
            | ["agent", "id", "directory", "entrypoint"] as $required
            | ($required | map(select($r[.] == null or $r[.] == ""))) as $missing
            | if $missing != [] then error("required: " + ($missing | join(", "))) else . end
            | ["agent", "id", "directory", "entrypoint", "topic", "title", "note"]
            | map($r[.] // "" | tostring)
        ' <<<"$input" 2>&1) || { echo "Error: ${record#jq: error (at <stdin>:*): }" >&2; exit 1; }
        fields=()
        while IFS= read -r -d '' value; do fields+=("$value"); done < <(jq -j '.[] + "\u0000"' <<<"$record")
        # The whole record, replacing the one there or creating it. There is no
        # partial write: the caller reads, decides and writes it back entire,
        # so what is in the store is always something a caller meant.
        query "INSERT INTO sessions (agent, id, directory, entrypoint, topic, title, note)
               VALUES ($(sql "${fields[0]}"), $(sql "${fields[1]}"), $(sql "${fields[2]}"), $(sql "${fields[3]}"),
                       $(sql "${fields[4]}"), $(sql "${fields[5]}"), $(sql "${fields[6]}"))
               ON CONFLICT (agent, id) DO UPDATE SET
                   directory = excluded.directory, entrypoint = excluded.entrypoint,
                   topic = excluded.topic, title = excluded.title, note = excluded.note;" \
            || exit 1
        ;;
    *)
        echo "Usage: $(basename "$0") get|list|write ..." >&2
        exit 1
        ;;
esac

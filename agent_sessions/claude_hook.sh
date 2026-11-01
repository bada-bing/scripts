#!/usr/bin/env bash
#
# claude_hook - Claude Code's hook into the agent session store.
#
# Records the session, links it to its topic and titles it, all read off the
# tmux window the agent runs in: the tmux session's name gives the topic when
# it names a task with a page, and the window gives the title. This is the one
# place tmux is read; the store is written only through agent_session.sh, and
# the hook writes nothing of its own.
#
# Usage, from settings.json:   claude_hook.sh            the hook's JSON on stdin
# Usage, by hand in a window:  claude_hook.sh --report [<session-id>]
#                                                        what it resolves there
#
# It never stops or delays the session: whatever fails, it exits 0.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TASK_PAGE="$SCRIPT_DIR/../work_session/find_task_page.sh"

# The pane the session really runs in, and no other. The environment is not
# consulted: TMUX_PANE survives on the daemon that supervises background
# sessions, inherited from whichever window happened to start it, and every
# session under it would be attributed to that window. Two chains tie a hook
# to a pane and nothing else does. A foreground session, fresh or resumed
# with --resume, runs under the pane's shell, so the shell is an ancestor of
# the hook. A background session runs under the daemon, so its hook has no
# pane of its own; once it is attached, the client in the pane names the
# session on its command line, and the pane is the client's. Neither chain
# holds for an unattached background session, which gets no pane.
pane_of_process() {
    local pid="$1" panes
    panes=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null) || return
    while [[ "$pid" -gt 1 ]]; do
        awk -v p="$pid" '$1 == p { print $2; found = 1 } END { exit !found }' <<<"$panes" && return
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [[ -z "$pid" ]] && return
    done
    return 1
}

pane() {
    local client
    pane_of_process $$ && return
    [[ -z "$session_id" ]] && return
    client=$(pgrep -f "claude (attach|--resume|-r) ${session_id:0:8}" | head -1)
    [[ -n "$client" ]] && pane_of_process "$client"
}

# The topic the address gives: the tmux session's name, when it is a task
# with a page. A task session is named for its key, so the name is tried as
# one and nothing else - default, a repository, a discussion session or an
# ad hoc name resolves to no page and gives no topic. The shape is checked
# first so that a repository whose name happens to be a page, health, is
# never taken for a task.
key_of() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z0-9]+[-_.][A-Za-z0-9]*[0-9]+$ ]] || return
    "$TASK_PAGE" "$name" >/dev/null 2>&1 && printf '%s' "$name"
}

# How the session was started: cli for an interactive one, sdk-cli for a
# one-shot. Claude Code sets CLAUDE_CODE_ENTRYPOINT in the hook's environment
# at SessionStart, when the transcript does not exist yet, so that is read
# first; the transcript's own entrypoint field covers a hook run without it,
# and unknown is recorded rather than nothing, since the field is required.
entrypoint() {
    local transcript="$1" value="${CLAUDE_CODE_ENTRYPOINT:-}"
    [[ -z "$value" && -f "$transcript" ]] \
        && value=$(grep -m1 -o '"entrypoint":"[^"]*"' "$transcript" | cut -d'"' -f4)
    printf '%s' "${value:-unknown}"
}

[[ "${1:-}" == "--report" ]] && report=true || report=false
report_id="${2:-}"

# The hook's input: what Claude Code hands in on stdin. Run by hand there is
# none, and the transcript path is read where the status bar left it, on the
# window.
input=""
$report || input=$(cat)
session_id=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null)
[[ -n "$report_id" ]] && session_id="$report_id"
transcript_path=$(jq -r '.transcript_path // ""' <<<"$input" 2>/dev/null)
[[ -z "$transcript_path" && -n "${TMUX_PANE:-}" ]] \
    && transcript_path=$(tmux show-option -qvw -t "$TMUX_PANE" @claude_transcript 2>/dev/null)

pane=$(pane)
session_name="" window_name="" auto_rename="" key="" title=""
if [[ -n "$pane" ]]; then
    IFS=$'\t' read -r session_name window_name auto_rename < <(
        tmux display-message -p -t "$pane" $'#{session_name}\t#{window_name}\t#{automatic-rename}' 2>/dev/null)
    key=$(key_of "$session_name")
    # The title follows the window: the tmux session's name alone while the
    # window is still automatically named, the address once it is named.
    if [[ "$auto_rename" == "1" ]]; then title="$session_name"; else title="$session_name:$window_name"; fi
fi

event=$(jq -r '.hook_event_name // ""' <<<"$input" 2>/dev/null)
cwd=$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null)

existing='{}'
# Compact, as the wanted record is built, so the two compare as strings.
[[ -n "$session_id" ]] && existing=$("$SCRIPT_DIR/agent_session.sh" get claude "$session_id" 2>/dev/null | jq -c .)
[[ -z "$existing" ]] && existing='{}'
recorded_title=$(jq -r '.title // ""' <<<"$existing")
# The directory and the entry point are facts of the start: a record that
# exists keeps them whatever the input says, and only one being created
# takes them from the input and the environment.
directory=$(jq -r '.directory // ""' <<<"$existing")
[[ -z "$directory" ]] && directory="$cwd"

# The title the session carries now. Claude Code keeps it in the transcript,
# one custom-title entry per change, the last one current; a title the hook
# set through sessionTitle lands there the same way as -n or /rename. The
# transcript is not on disk at start nor at the first prompt, and a name
# given with -n is then known only to the agents listing. That listing also
# names what was not named: an interactive session <directory>-xx, and a
# background session after its prompt, so a background session's name
# counts only when it is shaped <key>:<role>. Without a title from either
# source the title is taken to be the one the hook wrote last, so a first
# prompt sets nothing again.
claude_title=""
if [[ -f "$transcript_path" ]]; then
    claude_title=$(grep '"type":"custom-title"' "$transcript_path" | tail -1 | jq -r '.customTitle // ""' 2>/dev/null)
elif [[ -n "$session_id" ]]; then
    IFS=$'\t' read -r kind name < <(claude agents --json 2>/dev/null \
        | jq -r --arg id "$session_id" '.[] | select(.sessionId == $id) | [.kind // "", .name // ""] | @tsv' 2>/dev/null | head -1)
    claude_title="$recorded_title"
    if [[ "$kind" == "interactive" && -n "$name" && ! "$name" =~ ^"$(basename "$directory")"-[0-9a-f]{2}$ ]]; then
        claude_title="$name"
    elif [[ "$kind" != "interactive" && "$name" =~ ^[A-Za-z0-9_.-]+:[A-Za-z0-9_-]+$ ]]; then
        claude_title="$name"
    fi
fi

# A title that is neither the one the hook wrote last nor the address was
# given by hand: it names the window, and the hook keeps it rather than
# writing the address over it, for as long as the window carries it. With
# no pane there is no address, so the title is whatever the session carries,
# and a name shaped <key>:<role> with a page for the key gives the topic:
# a background session started with -n 10x_06:worker is 10x_06's.
hand_named=false
if [[ -n "$claude_title" ]]; then
    if [[ -n "$pane" ]]; then
        if [[ "$claude_title" != "$recorded_title" && "$claude_title" != "$title" ]]; then
            hand_named=true
            $report || tmux rename-window -t "$pane" "$claude_title" 2>/dev/null
            title="$claude_title"
        elif [[ "$claude_title" == "$window_name" ]]; then
            title="$claude_title"
        fi
    else
        title="$claude_title"
        [[ "$claude_title" =~ ^([^:]+): ]] && key=$(key_of "${BASH_REMATCH[1]}")
    fi
fi

# The record as it should be: the title and the topic off the window, the
# rest as it was recorded. The address can give a topic and never take one, so a window where no
# task answers keeps the topic the record has; the note is never the hook's
# to write, so it is the record's own. A session with nothing recorded yet
# starts with both empty.
wanted=$(jq -nc --argjson old "$existing" \
    --arg id "$session_id" --arg directory "$directory" --arg entrypoint "$(entrypoint "$transcript_path")" \
    --arg key "$key" --arg title "$title" '
    {agent: "claude", id: $id, directory: $directory, entrypoint: ($old.entrypoint // $entrypoint),
     topic: (if $key != "" then $key else ($old.topic // "") end),
     title: $title, note: ($old.note // "")}')

# Every prompt compares and writes only what differs: the record when it is
# not the one in the store, the title when it is not the one the session
# carries. A prompt on which nothing moved touches nothing. A start, fresh,
# resumed, after /clear or after compaction, also hands the agent its start context: the
# topic, its other sessions and where the work stands, from start_context.sh.
topic=$(jq -r '.topic // ""' <<<"$wanted")
case "$event" in
    SessionStart | UserPromptSubmit)
        [[ -n "$session_id" && "$wanted" != "$existing" ]] \
            && printf '%s' "$wanted" | "$SCRIPT_DIR/agent_session.sh" write 2>/dev/null
        output='{}'
        [[ -n "$title" && "$title" != "$claude_title" ]] \
            && output=$(jq -c --arg title "$title" '. + {sessionTitle: $title}' <<<"$output")
        if [[ "$event" == "SessionStart" ]]; then
            start_context=$("$SCRIPT_DIR/start_context.sh" "$topic" "$session_id" "$auto_rename" 2>/dev/null)
            [[ -n "$start_context" ]] \
                && output=$(jq -c --arg text "$start_context" '. + {additionalContext: $text}' <<<"$output")
        fi
        [[ "$output" != '{}' ]] \
            && jq -c --arg event "$event" '{hookSpecificOutput: ({hookEventName: $event} + .)}' <<<"$output"
        ;;
esac

if $report; then
    echo "pane:       ${pane:-(outside tmux)}"
    echo "session:    ${session_name:-(none)}"
    echo "window:     ${window_name:-(none)}$([[ "$auto_rename" == 1 ]] && echo ' (automatically named)')"
    echo "topic:      ${key:-(no task)}"
    echo "title:      ${title:-(none)}$($hand_named && echo ' (given by hand, would rename the window)')"
    echo "entrypoint: $(entrypoint "$transcript_path")"
    echo "start context:"
    "$SCRIPT_DIR/start_context.sh" "$topic" "$session_id" "$auto_rename" | sed 's/^/  /'
    if [[ -z "$session_id" ]]; then
        echo "record:     no session id, pass one"
    elif [[ "$existing" == '{}' ]]; then
        echo "record:     none, would write $wanted"
    elif [[ "$wanted" == "$existing" ]]; then
        echo "record:     as it should be, topic ${recorded_title:+}$(jq -r '.topic | if . == "" then "(no task)" else . end' <<<"$existing"), title $(jq -r .title <<<"$existing")"
    else
        echo "record:     $(jq -c . <<<"$existing")"
        echo "would write $wanted"
    fi
fi

exit 0

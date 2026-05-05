#!/usr/bin/env bash
# Register this Claude Code session in the claude-ipc peers file.
# Invoked as a SessionStart hook; reads JSON {session_id, cwd, ...} on stdin.
set -euo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$SID" ] && [ -n "$CWD" ] || exit 0

STATE_DIR="$HOME/.claude/claude-ipc"
SESSIONS_DIR="$STATE_DIR/sessions"
mkdir -p "$SESSIONS_DIR"

# Walk up the parent chain to find the long-lived `claude` process
# that owns this session. $PPID here is a short-lived intermediate
# spawned by Claude to run the hook, so we cannot rely on it. Tool-
# call bash subprocesses walk the same chain to find the same pid.
find_claude_pid() {
  local pid=$$
  local cmd
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null) || return 1
    case "$cmd" in
      claude|claude\ *|*/claude|*/claude\ *) printf '%s\n' "$pid"; return 0 ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
  done
  return 1
}
CLAUDE_PID=$(find_claude_pid) || CLAUDE_PID=""
if [ -n "$CLAUDE_PID" ]; then
  printf '%s\n' "$SID" > "$SESSIONS_DIR/$CLAUDE_PID.sid"
fi

# Resolve message_file location (default or config override).
CONFIG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
MSGFILE=""
if [ -f "$CONFIG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"

PEERS_DIR=$(dirname "$MSGFILE")
mkdir -p "$PEERS_DIR"
PEERS="$PEERS_DIR/claude-ipc-peers.jsonl"
LOCK="$PEERS.lock"
touch "$PEERS" "$LOCK"

ENTRY=$(jq -cn \
  --arg ts   "$(date -u +%FT%TZ)" \
  --arg sid  "$SID" \
  --arg cwd  "$CWD" \
  --arg host "$(hostname)" \
  '{ts:$ts, sid:$sid, cwd:$cwd, host:$host}')

(
  flock 9
  TMP=$(mktemp)
  if [ -s "$PEERS" ]; then
    jq -c --arg sid "$SID" 'select(.sid != $sid)' "$PEERS" > "$TMP" || true
  fi
  printf '%s\n' "$ENTRY" >> "$TMP"
  mv "$TMP" "$PEERS"
) 9>"$LOCK"

exit 0

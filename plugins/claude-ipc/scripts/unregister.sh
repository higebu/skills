#!/usr/bin/env bash
# Remove this Claude Code session from the claude-ipc peers file.
# Invoked as a SessionEnd hook; reads JSON {session_id, ...} on stdin.
set -euo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -n "$SID" ] || exit 0

STATE_DIR="$HOME/.claude/claude-ipc"
SESSIONS_DIR="$STATE_DIR/sessions"

# Best-effort: drop the per-session marker file.
find_claude_pid() {
  local pid=$$ cmd
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null) || return 1
    case "$cmd" in
      claude|claude\ *|*/claude|*/claude\ *) printf '%s\n' "$pid"; return 0 ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
  done
  return 1
}
CLAUDE_PID=$(find_claude_pid 2>/dev/null) || CLAUDE_PID=""
[ -n "$CLAUDE_PID" ] && rm -f "$SESSIONS_DIR/$CLAUDE_PID.sid" 2>/dev/null || true

CONFIG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
MSGFILE=""
if [ -f "$CONFIG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"

PEERS_DIR=$(dirname "$MSGFILE")
PEERS="$PEERS_DIR/claude-ipc-peers.jsonl"
LOCK="$PEERS.lock"
[ -f "$PEERS" ] || exit 0
touch "$LOCK"

(
  flock 9
  TMP=$(mktemp)
  jq -c --arg sid "$SID" 'select(.sid != $sid)' "$PEERS" > "$TMP" || true
  mv "$TMP" "$PEERS"
) 9>"$LOCK"

exit 0

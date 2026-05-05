#!/usr/bin/env bash
# Remove this Claude Code session from the claude-ipc peers file.
# Invoked as a SessionEnd hook; reads JSON {session_id, ...} on stdin.
set -euo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -n "$SID" ] || exit 0

STATE_DIR="$HOME/.claude/claude-ipc"
SESSIONS_DIR="$STATE_DIR/sessions"
rm -f "$SESSIONS_DIR/$PPID.sid" 2>/dev/null || true

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

#!/usr/bin/env bash
# Register this Claude Code session in the claude-ipc peers file.
# Invoked as a SessionStart hook; reads JSON {session_id, cwd, ...} on stdin.
set -euo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$SID" ] && [ -n "$CWD" ] || exit 0

STATE_DIR="$HOME/.claude/claude-ipc"
mkdir -p "$STATE_DIR"

# Export the session_id into every subsequent Bash tool call via
# the documented CLAUDE_ENV_FILE mechanism (SessionStart hook only).
# https://code.claude.com/docs/en/hooks.md
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  printf 'CLAUDE_IPC_SID=%s\n' "$SID" >> "$CLAUDE_ENV_FILE"
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

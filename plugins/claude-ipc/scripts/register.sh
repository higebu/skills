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

# Walk up to find the long-lived `claude` process. Recording its pid
# in the peer entry lets us drop /clear orphans on re-register: a
# /clear changes session_id without firing SessionEnd, so the old
# entry is otherwise undeletable. Same (host, claude_pid) means same
# Claude process → safe to evict on re-register.
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
HOST=$(hostname)

ENTRY=$(jq -cn \
  --arg ts   "$(date -u +%FT%TZ)" \
  --arg sid  "$SID" \
  --arg cwd  "$CWD" \
  --arg host "$HOST" \
  --arg pid  "$CLAUDE_PID" \
  '{ts:$ts, sid:$sid, cwd:$cwd, host:$host, pid:$pid}')

(
  flock 9
  TMP=$(mktemp)
  if [ -s "$PEERS" ]; then
    # Drop entries with the same sid (idempotent re-register) AND
    # entries with the same (host, pid) when pid is known
    # (/clear orphans from the same Claude process).
    jq -c \
      --arg sid  "$SID" \
      --arg host "$HOST" \
      --arg pid  "$CLAUDE_PID" '
      select(.sid != $sid)
      | select($pid == "" or (.pid // "") != $pid or (.host // "") != $host)
    ' "$PEERS" > "$TMP" || true
  fi
  printf '%s\n' "$ENTRY" >> "$TMP"
  mv "$TMP" "$PEERS"
) 9>"$LOCK"

exit 0

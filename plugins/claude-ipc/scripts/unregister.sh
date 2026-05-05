#!/usr/bin/env bash
# SessionEnd hook for claude-ipc — drop this session's peer entry
# (best effort — keyed by claude_pid + host).
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

STATE_DIR="$HOME/.claude/claude-ipc"
SESSIONS_DIR="$STATE_DIR/sessions"

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

[ -n "$CLAUDE_PID" ] && rm -f "$SESSIONS_DIR/$CLAUDE_PID.name" 2>/dev/null || true

CONFIG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
MSGFILE=""
if [ -f "$CONFIG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"
PEERS="$(dirname "$MSGFILE")/claude-ipc-peers.jsonl"
LOCK="$PEERS.lock"
[ -f "$PEERS" ] || exit 0
touch "$LOCK"

(
  flock 9
  TMP=$(mktemp)
  jq -c \
    --arg host "$HOST" \
    --arg pid  "$CLAUDE_PID" \
    --arg cwd  "$CWD" '
    select($pid == "" or (.host // "") != $host or (.pid // "") != $pid)
    | select($cwd == "" or (.cwd // "") != $cwd or (.host // "") != $host or (.pid // "") != $pid)
  ' "$PEERS" > "$TMP" || true
  mv "$TMP" "$PEERS"
) 9>"$LOCK"

exit 0

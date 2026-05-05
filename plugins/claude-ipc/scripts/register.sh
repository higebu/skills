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

# Export the session_id into every subsequent Bash tool call via
# the documented CLAUDE_ENV_FILE mechanism (SessionStart hook only).
# https://code.claude.com/docs/en/hooks.md
# Best-effort: not every Claude Code version honours this on hook
# completion, so we also write a pid-keyed marker file below as a
# robust fallback.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  printf 'CLAUDE_IPC_SID=%s\n' "$SID" >> "$CLAUDE_ENV_FILE"
fi

# One-line debug breadcrumb per fire so we can diagnose env-file
# propagation issues without needing the user to dump env manually.
{
  printf '%s register sid=%s cwd=%s env_file=%s plugin_root=%s\n' \
    "$(date -u +%FT%TZ)" "$SID" "$CWD" \
    "${CLAUDE_ENV_FILE:-(unset)}" "${CLAUDE_PLUGIN_ROOT:-(unset)}"
} >> "$STATE_DIR/hook.log"

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

# Marker file fallback so send/recv/config can still find the per-
# session sid when CLAUDE_ENV_FILE did not propagate.
if [ -n "$CLAUDE_PID" ]; then
  printf '%s\n' "$SID" > "$SESSIONS_DIR/$CLAUDE_PID.sid"
fi

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

#!/usr/bin/env bash
# SessionStart hook for claude-ipc.
# - Looks up this cwd's user-assigned name.
# - If a name is configured, registers it in the peers file and emits
#   helpful context to the LLM.
# - If no name is configured, emits an additionalContext nudge so the
#   LLM tells the user to run /claude-ipc:config name <NAME>.
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || exit 0

STATE_DIR="$HOME/.claude/claude-ipc"
NAMES_DIR="$STATE_DIR/cwd-names"
mkdir -p "$NAMES_DIR"

CWD_HASH=$(printf '%s' "$CWD" | sha1sum | cut -c1-12)
NAME_FILE="$NAMES_DIR/$CWD_HASH.name"

NAME=""
if [ -s "$NAME_FILE" ]; then
  NAME=$(head -1 "$NAME_FILE" | tr -d '\n')
fi

emit_context() {
  jq -cn --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
}

if [ -z "$NAME" ]; then
  emit_context "claude-ipc is installed but this working directory has no name yet. Run \`/claude-ipc:config name <NAME>\` (e.g. \`name $(basename "$CWD")\`) before sending or receiving messages. cwd: $CWD"
  exit 0
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

# Find the long-lived claude process (parent-chain walk).
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
TS=$(date -u +%FT%TZ)

# Export name into subsequent Bash tool calls (env file is *.sh that
# Claude Code sources). We also write a marker file as a robust
# fallback for Claude Code versions that don't honour CLAUDE_ENV_FILE.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  printf 'export CLAUDE_IPC_NAME=%q\n' "$NAME" >> "$CLAUDE_ENV_FILE"
  printf 'export CLAUDE_IPC_CWD=%q\n' "$CWD" >> "$CLAUDE_ENV_FILE"
fi
if [ -n "$CLAUDE_PID" ]; then
  SESSIONS_DIR="$STATE_DIR/sessions"
  mkdir -p "$SESSIONS_DIR"
  printf '%s\n' "$NAME" > "$SESSIONS_DIR/$CLAUDE_PID.name"
  # GC dead pid markers
  for m in "$SESSIONS_DIR"/*.name; do
    [ -e "$m" ] || break
    base=$(basename "$m" .name)
    case "$base" in *[!0-9]*) continue ;; esac
    kill -0 "$base" 2>/dev/null || rm -f "$m"
  done
fi

ENTRY=$(jq -cn \
  --arg ts   "$TS" \
  --arg name "$NAME" \
  --arg cwd  "$CWD" \
  --arg host "$HOST" \
  --arg pid  "$CLAUDE_PID" \
  '{ts:$ts, name:$name, cwd:$cwd, host:$host, pid:$pid}')

(
  flock 9
  TMP=$(mktemp)
  if [ -s "$PEERS" ]; then
    # Drop entries with the same (host, name) — same instance re-registering
    # OR same (host, claude_pid) — /clear orphan from same Claude process.
    jq -c \
      --arg name "$NAME" \
      --arg host "$HOST" \
      --arg pid  "$CLAUDE_PID" '
      select((.host // "") != $host or (.name // "") != $name)
      | select($pid == "" or (.host // "") != $host or (.pid // "") != $pid)
    ' "$PEERS" > "$TMP" || true
  fi
  printf '%s\n' "$ENTRY" >> "$TMP"
  mv "$TMP" "$PEERS"
) 9>"$LOCK"

# Tell the LLM who it is and (briefly) who else is online.
ALIVE=$(jq -rs --arg me "$NAME" \
  '[.[] | select(.name != $me) | .name] | unique | join(", ")' "$PEERS")
[ -z "$ALIVE" ] && ALIVE="(no other peers online)"
emit_context "claude-ipc identity: name=$NAME, cwd=$CWD. Other peers online: $ALIVE. Send with /claude-ipc:send <name> <msg>; receive with /claude-ipc:recv or /claude-ipc:watch."

{
  printf '%s register name=%s cwd=%s pid=%s env_file=%s\n' \
    "$TS" "$NAME" "$CWD" "$CLAUDE_PID" "${CLAUDE_ENV_FILE:-(unset)}"
} >> "$STATE_DIR/hook.log"

exit 0

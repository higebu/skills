#!/usr/bin/env bash
# SessionStart hook for claude-ipc.
# - Reads the cwd's user-given name from
#   ~/.claude/claude-ipc/cwd-names/<sha1>.name (set by /claude-ipc:config).
# - If no name is configured, emits hookSpecificOutput.additionalContext
#   nudging the LLM to ask the user to run /claude-ipc:config name <NAME>.
#   No peer entry is registered.
# - Otherwise registers a peer entry in the peers JSONL.
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
[ -s "$NAME_FILE" ] && NAME=$(head -1 "$NAME_FILE" | tr -d '\n')

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

HOST=$(hostname)
TS=$(date -u +%FT%TZ)

ENTRY=$(jq -cn \
  --arg ts   "$TS" \
  --arg name "$NAME" \
  --arg cwd  "$CWD" \
  --arg host "$HOST" \
  '{ts:$ts, name:$name, cwd:$cwd, host:$host}')

(
  flock 9
  TMP=$(mktemp)
  if [ -s "$PEERS" ]; then
    # Drop any prior entry for the same (host, name) — re-register.
    jq -c --arg name "$NAME" --arg host "$HOST" '
      select((.host // "") != $host or (.name // "") != $name)
    ' "$PEERS" > "$TMP" || true
  fi
  printf '%s\n' "$ENTRY" >> "$TMP"
  mv "$TMP" "$PEERS"
) 9>"$LOCK"

ALIVE=$(jq -rs --arg me "$NAME" \
  '[.[] | select(.name != $me) | .name] | unique | join(", ")' "$PEERS")
[ -z "$ALIVE" ] && ALIVE="(no other peers online)"
emit_context "claude-ipc identity: name=$NAME, cwd=$CWD. Other peers online: $ALIVE. Send with /claude-ipc:send <name> <msg>; receive with /claude-ipc:recv or /claude-ipc:watch."

exit 0

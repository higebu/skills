#!/usr/bin/env bash
# SessionEnd hook — drop this cwd's peer entry by (host, name).
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || exit 0

STATE_DIR="$HOME/.claude/claude-ipc"
NAMES_DIR="$STATE_DIR/cwd-names"
CWD_HASH=$(printf '%s' "$CWD" | sha1sum | cut -c1-12)
NAME_FILE="$NAMES_DIR/$CWD_HASH.name"

NAME=""
[ -s "$NAME_FILE" ] && NAME=$(head -1 "$NAME_FILE" | tr -d '\n')
[ -n "$NAME" ] || exit 0

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

HOST=$(hostname)
(
  flock 9
  TMP=$(mktemp)
  jq -c --arg name "$NAME" --arg host "$HOST" '
    select((.host // "") != $host or (.name // "") != $name)
  ' "$PEERS" > "$TMP" || true
  mv "$TMP" "$PEERS"
) 9>"$LOCK"

exit 0

#!/usr/bin/env bash
# SessionStart hook for claude-ipc.
#
# Mailbox model: messages persist in messages.jsonl whether or not
# the recipient is online. This hook runs at session start, reads
# any unread messages addressed to this cwd's NAME, and surfaces
# them to the LLM as hookSpecificOutput.additionalContext. The
# cursor is then advanced so /claude-ipc:recv won't re-deliver them.
#
# If the cwd has no NAME configured, emit a nudge instead.
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || exit 0

STATE_DIR="$HOME/.claude/claude-ipc"
NAMES_DIR="$STATE_DIR/cwd-names"
mkdir -p "$NAMES_DIR"

CWD_HASH=$(printf '%s' "$CWD" | sha1sum | cut -c1-12)
NAME_FILE="$NAMES_DIR/$CWD_HASH.name"

emit_context() {
  jq -cn --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
}

if [ ! -s "$NAME_FILE" ]; then
  emit_context "claude-ipc is installed but this working directory has no name yet. Run \`/claude-ipc:config name <NAME>\` (e.g. \`name $(basename "$CWD")\`) before sending or receiving messages. cwd: $CWD"
  exit 0
fi
NAME=$(head -1 "$NAME_FILE" | tr -d '\n')

# Resolve message_file location (default or config override).
CONFIG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
MSGFILE=""
if [ -f "$CONFIG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"

CURSOR_FILE="$STATE_DIR/cursor-$NAME"
SIZE=0
[ -f "$MSGFILE" ] && SIZE=$(stat -c%s "$MSGFILE" 2>/dev/null || stat -f%z "$MSGFILE")

# First-time use: jump to current EOF, no historical replay on first launch.
if [ ! -s "$CURSOR_FILE" ]; then
  printf '%s\n' "$SIZE" > "$CURSOR_FILE"
  emit_context "claude-ipc identity: name=$NAME, cwd=$CWD. Mailbox initialized — no unread messages. Send: /claude-ipc:send <name> <msg>; receive: /claude-ipc:recv; live: /claude-ipc:watch."
  exit 0
fi

OFFSET=$(cat "$CURSOR_FILE")
[ "$OFFSET" -gt "$SIZE" ] && OFFSET=0  # rotation guard

if [ "$OFFSET" -ge "$SIZE" ]; then
  emit_context "claude-ipc identity: name=$NAME, cwd=$CWD. No new messages."
  printf '%s\n' "$SIZE" > "$CURSOR_FILE"
  exit 0
fi

UNREAD=$(tail -c +$((OFFSET + 1)) "$MSGFILE" | \
  jq -r --arg me "$NAME" '
    select(.to == $me)
    | "[\(.ts)] from \(.from) (\(.from_cwd // "?")): \(.msg)"
  ' 2>/dev/null || true)

# Advance cursor regardless (we have read up to current EOF).
printf '%s\n' "$SIZE" > "$CURSOR_FILE"

if [ -z "$UNREAD" ]; then
  emit_context "claude-ipc identity: name=$NAME, cwd=$CWD. No new messages addressed here."
  exit 0
fi

COUNT=$(printf '%s\n' "$UNREAD" | grep -c '^\[')
TAIL=$(printf '%s\n' "$UNREAD" | tail -n 20)
SUFFIX=""
if [ "$COUNT" -gt 20 ]; then
  SUFFIX=$'\n\n... and '"$((COUNT - 20))"' earlier message(s) — use /claude-ipc:history all to see them.'
fi
emit_context "claude-ipc — $COUNT unread message(s) for $NAME (cwd $CWD):\n\n$TAIL$SUFFIX"
exit 0

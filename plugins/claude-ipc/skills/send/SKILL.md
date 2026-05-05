---
name: send
description: >
  Send a message to another Claude Code instance by its NAME (assigned
  via /claude-ipc:config). Trigger phrases: "別のClaudeに伝えて",
  "他のエージェントに送って", "send to another Claude".
argument-hint: "<recipient-name> <message>"
allowed-tools: Bash
---

# Send a message to a named claude-ipc peer

## Step 1: Resolve message file + my name

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
CFG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
if [ -f "$CFG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CFG" | head -1); MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"
mkdir -p "$STATE_DIR" "$(dirname "$MSGFILE")"
touch "$MSGFILE" "$MSGFILE.lock"

resolve_my_name() {
  if [ -n "${CLAUDE_IPC_NAME:-}" ]; then printf '%s\n' "$CLAUDE_IPC_NAME"; return 0; fi
  local pid=$$ cmd
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null) || return 1
    case "$cmd" in
      claude|claude\ *|*/claude|*/claude\ *)
        local f="$STATE_DIR/sessions/$pid.name"
        [ -s "$f" ] && cat "$f" && return 0
        return 1 ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
  done
  # Last resort: cwd-names file
  local h
  h=$(printf '%s' "$PWD" | sha1sum | cut -c1-12)
  [ -s "$STATE_DIR/cwd-names/$h.name" ] && cat "$STATE_DIR/cwd-names/$h.name"
}
FROM=$(resolve_my_name) || FROM=""
[ -n "$FROM" ] || { echo "Error: this cwd has no claude-ipc name. Run /claude-ipc:config name <NAME> first." >&2; exit 1; }
```

## Step 2: Validate inputs

`<TO>` is the user's first argument (recipient name). `<MSG>` is the
remainder (the message body, single literal string). Substitute when
assembling the bash.

```bash
TO='<TO>'
MSG='<MSG>'
[ -n "$TO" ] && [ -n "$MSG" ] || {
  echo "Usage: /claude-ipc:send <recipient-name> <message>" >&2; exit 1
}
[[ "$TO" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid recipient name: $TO" >&2; exit 1; }
```

## Step 3: Append the JSON line

```bash
ENTRY=$(jq -cn \
  --arg ts   "$(date -u +%FT%TZ)" \
  --arg from "$FROM" \
  --arg fcwd "$PWD" \
  --arg to   "$TO" \
  --arg msg  "$MSG" \
  '{ts:$ts, from:$from, from_cwd:$fcwd, to:$to, msg:$msg}')

( flock 9; printf '%s\n' "$ENTRY" >> "$MSGFILE" ) 9>"$MSGFILE.lock"

echo "Sent $FROM -> $TO via $MSGFILE"
echo "  $MSG"
```

## Step 4: Verify recipient exists (warn-only)

```bash
PEERS_FILE="$(dirname "$MSGFILE")/claude-ipc-peers.jsonl"
if [ -s "$PEERS_FILE" ]; then
  if ! jq -e --arg n "$TO" 'select(.name == $n)' "$PEERS_FILE" >/dev/null 2>&1; then
    echo "(warning: no peer currently registered with name '$TO' — message stored anyway)" >&2
  fi
fi
```

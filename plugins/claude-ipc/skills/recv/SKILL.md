---
name: recv
description: >
  Read new messages addressed to my NAME (set via /claude-ipc:config).
  Tracks a per-name byte-offset cursor so only unread messages are
  shown; pass --all to replay everything addressed here. Trigger
  phrases: "メッセージを確認して", "新着ある?", "check messages".
argument-hint: "[--all]"
allowed-tools: Bash
---

# Read new messages addressed to my name

## Step 1: Resolve message file + my name + cursor

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
CFG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
if [ -f "$CFG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CFG" | head -1); MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"
[ -f "$MSGFILE" ] || { echo "No messages yet."; exit 0; }

CWD_HASH=$(printf '%s' "$PWD" | sha1sum | cut -c1-12)
NAME_FILE="$STATE_DIR/cwd-names/$CWD_HASH.name"
[ -s "$NAME_FILE" ] || { echo "Error: no claude-ipc name. Run /claude-ipc:config name <NAME>." >&2; exit 1; }
NAME=$(head -1 "$NAME_FILE" | tr -d '\n')

# Per-name cursor — stable across Claude restarts.
CURSOR_FILE="$STATE_DIR/cursor-$NAME"
SIZE=$(stat -c%s "$MSGFILE" 2>/dev/null || stat -f%z "$MSGFILE")
ALL=<0_OR_1>   # substitute 1 if user passed --all, else 0
if [ "$ALL" = "1" ]; then
  OFFSET=0
elif [ ! -s "$CURSOR_FILE" ]; then
  OFFSET=$SIZE
else
  OFFSET=$(cat "$CURSOR_FILE")
fi
[ "$OFFSET" -gt "$SIZE" ] && OFFSET=0
```

## Step 2: Print new messages addressed to my name

```bash
COUNT=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  printf '%s\n' "$line" | jq -e --arg me "$NAME" \
    'select(.to == $me)
     | "[\(.ts)] from \(.from) (\(.from_cwd)):\n  \(.msg)\n"' \
    -r 2>/dev/null && COUNT=$((COUNT+1))
done < <(tail -c +$((OFFSET + 1)) "$MSGFILE")

[ "$COUNT" -eq 0 ] && echo "No new messages for $NAME."
```

## Step 3: Advance cursor

```bash
[ "$ALL" = "0" ] && printf '%s\n' "$SIZE" > "$CURSOR_FILE"
```

## Notes

- Cursor is per-NAME, so a Claude restart, `/clear`, or even
  reinstall does **not** lose your read position.
- `--all` reads everything from the start of the message file.
- A fresh name (never read before) starts at "now" (current EOF) so
  history is not flooded into the chat. Use `--all` to replay.

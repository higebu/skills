---
name: recv
description: >
  Read new messages addressed to the current working directory from
  the shared message file (default `~/.claude/messages.jsonl`,
  overridable via `~/.claude/claude-ipc/config`). Tracks a per-session
  byte-offset cursor so only unread messages are shown; pass `--all`
  to ignore the cursor and replay everything addressed here. Use when
  the user asks "メッセージを確認して", "新着ある?", "check messages",
  or before/after coordinating with another Claude Code instance.
argument-hint: "[--all]"
allowed-tools: Bash
---

# Read messages addressed to this working directory

Filter the shared JSONL by `to_cwd == $PWD`, advance the per-session
read cursor, and print new entries.

## Step 1: Resolve the message file

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
CONFIG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"

if [ -f "$CONFIG" ]; then
  MSGFILE=$(awk -F= '$1=="message_file"{print $2; exit}' "$CONFIG")
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"

mkdir -p "$STATE_DIR"
[ -f "$MSGFILE" ] || { echo "No messages yet (no $MSGFILE)."; exit 0; }
```

## Step 2: Resolve the session ID and cursor

```bash
SID_FILE="$STATE_DIR/sid"
if [ ! -s "$SID_FILE" ]; then
  uuidgen > "$SID_FILE"
fi
SID=$(cat "$SID_FILE")

CURSOR_FILE="$STATE_DIR/cursor-$SID"
if [ "$1" = "--all" ] || [ ! -s "$CURSOR_FILE" ]; then
  OFFSET=0
else
  OFFSET=$(cat "$CURSOR_FILE")
fi

SIZE=$(stat -c%s "$MSGFILE" 2>/dev/null || stat -f%z "$MSGFILE")
# guard against truncation/rotation: reset if the file shrank
[ "$OFFSET" -gt "$SIZE" ] && OFFSET=0
```

## Step 3: Print new messages addressed here

```bash
COUNT=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  printf '%s\n' "$line" | jq -e --arg cwd "$PWD" \
    'select(.to_cwd == $cwd)
     | "[\(.ts)] from \(.from_cwd) (sid=\(.session_id[0:8]))\n  \(.msg)\n"' \
    -r 2>/dev/null && COUNT=$((COUNT+1))
done < <(tail -c +$((OFFSET + 1)) "$MSGFILE")

if [ "$COUNT" -eq 0 ]; then
  echo "No new messages for $PWD."
fi
```

## Step 4: Advance the cursor

Only update the cursor when the user did *not* pass `--all`, so that
"replay everything" stays non-destructive.

```bash
if [ "$1" != "--all" ]; then
  printf '%s\n' "$SIZE" > "$CURSOR_FILE"
fi
```

## Notes

- The cursor is **per session ID** (per machine). It is not shared
  across hosts even when the message file is.
- Messages sent from this same `cwd` to itself will be shown; that is
  almost always a bug in the sender, so flag it to the user instead
  of silently filtering it out.
- The shared JSONL grows indefinitely. Outside of active sessions,
  rotate it with e.g.:
  ```bash
  mv ~/.claude/messages.jsonl ~/.claude/messages.$(date +%F).jsonl
  ```
  After rotation, run `/claude-ipc:recv --all` once on each instance
  so the cursor settles on the new (empty) file.

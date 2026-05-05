---
name: history
description: >
  Show past claude-ipc messages addressed to the current cwd, oldest
  first. Read-only — does not advance the recv cursor. Optional
  argument is the maximum number of entries to show (default 20). Use
  when the user asks "過去の履歴", "history", "show recent claude ipc
  traffic", or wants to scroll through past conversations.
argument-hint: "[N]"
allowed-tools: Bash
---

# Show claude-ipc message history for this cwd

Print past messages where `to_cwd == $PWD`, oldest first. Does not
touch the recv cursor, so this is safe to call at any time.

## Step 1: Resolve the message file

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
CONFIG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"

if [ -f "$CONFIG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"
[ -s "$MSGFILE" ] || { echo "No history yet."; exit 0; }
```

## Step 2: Print the last N entries addressed here

`<N>` is the user-supplied limit (default `20`). Substitute the
literal number when assembling the bash command.

```bash
jq -r --arg cwd "$PWD" '
  select(.to_cwd == $cwd)
  | "[\(.ts)] from \(.from_cwd) (sid=\(.session_id[0:8])): \(.msg)"
' "$MSGFILE" | tail -n <N>
```

If the user passes `all` instead of a number, drop the `tail` and
print every matching entry.

## Notes

- `history` is the read-only counterpart of `recv` (which advances
  the cursor) and `watch` (which streams future messages). Use them
  together: `history` to look back, `recv` for unread, `watch` for
  live.
- Output is in chronological order so the most recent message is at
  the bottom — easy to follow with the eye after a scroll-up.
- Sender + cwd + first 8 chars of session_id are shown so you can
  correlate with `/claude-ipc:peers` to identify whose message it is.

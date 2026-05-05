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
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"

mkdir -p "$STATE_DIR"
[ -f "$MSGFILE" ] || { echo "No messages yet (no $MSGFILE)."; exit 0; }
```

## Step 2: Resolve the session ID and cursor

```bash
# Per-session SID resolution: env var (CLAUDE_ENV_FILE) → pid-keyed
# marker file (set by SessionStart hook) → machine fallback.
SID="${CLAUDE_IPC_SID:-}"
if [ -z "$SID" ]; then
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
  if CLAUDE_PID=$(find_claude_pid); then
    M="$STATE_DIR/sessions/$CLAUDE_PID.sid"
    [ -s "$M" ] && SID=$(cat "$M")
  fi
fi
if [ -z "$SID" ]; then
  MACHINE_SID_FILE="$STATE_DIR/sid"
  [ -s "$MACHINE_SID_FILE" ] || uuidgen > "$MACHINE_SID_FILE"
  SID=$(cat "$MACHINE_SID_FILE")
fi

# Cursor is per-session: two sessions in the same cwd each maintain
# their own read position so neither swallows the other's notifications.
# A fresh session_id (Claude restart, /clear, etc.) means no cursor
# file yet; treat that as "start watching from now" so the first recv
# after a restart does not replay every historical message. Use --all
# to opt into a full replay.
CURSOR_FILE="$STATE_DIR/cursor-$SID"
SIZE=$(stat -c%s "$MSGFILE" 2>/dev/null || stat -f%z "$MSGFILE")
# Set ALL=1 if the user passed --all, else ALL=0. Substitute the
# concrete value when assembling the bash command.
ALL=<0_OR_1>
if [ "$ALL" = "1" ]; then
  OFFSET=0
elif [ ! -s "$CURSOR_FILE" ]; then
  OFFSET=$SIZE
else
  OFFSET=$(cat "$CURSOR_FILE")
fi

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
if [ "$ALL" = "0" ]; then
  printf '%s\n' "$SIZE" > "$CURSOR_FILE"
fi
```

## Notes

- The cursor is **per session ID**, matching Claude Code's own
  lifecycle: a Claude restart or `/clear` rotates the session_id and
  the new session naturally starts with a fresh cursor that points at
  the *current* end-of-file (so it only sees future messages, not
  history). Use `--all` to replay everything addressed here.
  Two Claude Code sessions in the same cwd each maintain their own
  cursor — both independently see every message addressed to that
  cwd (effectively a broadcast group). The cursor is local to this
  machine and is not shared across hosts even when the message file
  is.
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

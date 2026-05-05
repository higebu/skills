---
name: watch
description: >
  Start a background watcher (Monitor tool) that streams new
  claude-ipc messages addressed to the current cwd in real time. Each
  matching message arrives as a notification — no polling, no cursor
  bookkeeping. Use when the user asks "受信待ちにして", "watch for
  messages", "monitor claude ipc", or wants to stay reachable while
  doing other work.
argument-hint: ""
allowed-tools: Bash, Monitor
---

# Watch for incoming claude-ipc messages

Stream new messages addressed to `$PWD` as Monitor notifications,
running until the user stops it (`TaskStop`) or the session ends.

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

mkdir -p "$(dirname "$MSGFILE")"
touch "$MSGFILE"
```

Capture the resolved `$MSGFILE` and `$PWD` values — you will inline
them into the Monitor command in Step 2.

## Step 2: Launch the Monitor

Call the **Monitor** tool with:

- `persistent: true` — keep watching for the whole session.
- `description`: short and specific, e.g. `"claude-ipc messages for <PWD>"`.
- `command`: a `tail -F | jq` pipeline that emits one line per
  matching message. Use `tail -F` (capital F) so rotation doesn't
  break the stream, and pass `--unbuffered` to `jq` so each line is
  flushed immediately instead of being buffered:

```bash
tail -F -n 0 '<MSGFILE>' \
  | jq -r --unbuffered --arg cwd '<PWD>' '
      select(.to_cwd == $cwd)
      | "[\(.ts)] from \(.from_cwd) (sid=\(.session_id[0:8])): \(.msg)"
    '
```

`-n 0` skips the existing tail of the file so only **future**
messages trigger notifications. Drop `-n 0` if the user explicitly
asks to also surface recent history.

Substitute `<MSGFILE>` and `<PWD>` with the literal resolved values
when calling Monitor — do **not** rely on shell variables surviving
into the Monitor invocation.

## Step 3: Confirm to the user

Print a one-line confirmation so the user knows the watcher is armed:

```
Watching <MSGFILE> for messages addressed to <PWD>.
Stop with: TaskStop or end this session.
```

## Notes

- The watcher runs alongside normal interaction — you stay responsive
  to the user, and incoming messages appear as notifications you can
  react to or relay.
- `recv` and `watch` can coexist. `recv` advances the byte cursor;
  `watch` does not touch the cursor (it is purely live), so running
  both will not double-deliver.
- For cross-host setups, the watcher follows whatever `message_file`
  is configured — point it at the shared path with
  `/claude-ipc:config <path>` and `watch` automatically tails the
  shared file.
- If messages stop arriving as notifications, check that the writer
  side is appending newline-terminated JSONL and that `jq` is on the
  PATH; without `--unbuffered`, lines may sit in jq's stdio buffer
  for minutes.

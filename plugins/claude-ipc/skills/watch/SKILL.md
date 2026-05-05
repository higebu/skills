---
name: watch
description: >
  Background watcher (Monitor tool) that streams new claude-ipc
  messages addressed to my NAME in real time. Trigger phrases:
  "受信待ちにして", "watch for messages", "monitor claude ipc".
argument-hint: ""
allowed-tools: Bash, Monitor
---

# Live-watch incoming messages addressed to my name

## Step 1: Resolve message file + my name

Same logic as `recv` Step 1 — produce `MSGFILE` and `NAME`. If
`NAME` is empty, abort with the same error message.

## Step 2: Launch Monitor

Call **Monitor** with:

- `persistent: true`
- `description`: `claude-ipc messages for <NAME>`
- `command`:

```bash
tail -F -n 0 '<MSGFILE>' \
  | jq -r --unbuffered --arg me '<NAME>' '
      select(.to == $me)
      | "[\(.ts)] from \(.from) (\(.from_cwd)): \(.msg)"
    '
```

`-n 0` skips current EOF so only future entries fire notifications.
`--unbuffered` flushes per line (otherwise `jq` may buffer minutes
of output before emitting).

Substitute `<MSGFILE>` and `<NAME>` literally — do not rely on shell
variables surviving into the Monitor invocation.

## Step 3: Confirm

```
Watching <MSGFILE> for messages to <NAME>.
Stop with TaskStop or end this Claude session.
```

## Notes

- `recv` (cursor-tracked) and `watch` (live) coexist; watch does not
  touch the cursor.
- For cross-host setups, the watcher follows whatever
  `message_file` is configured.

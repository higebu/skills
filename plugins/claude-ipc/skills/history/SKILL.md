---
name: history
description: >
  Show past claude-ipc messages addressed to my NAME, oldest first.
  Read-only — does not advance the recv cursor. Trigger phrases:
  "過去の履歴", "history", "show recent claude ipc traffic".
argument-hint: "[N | all]"
allowed-tools: Bash
---

# Show claude-ipc message history for my name

## Step 1: Resolve message file + my name

Same as `recv` Step 1 — produce `MSGFILE` and `NAME`.

## Step 2: Print past entries

`<N>` is the user's argument (number or `all`; default `20`).

```bash
[ -s "$MSGFILE" ] || { echo "No history yet."; exit 0; }

if [ '<N>' = "all" ]; then
  jq -r --arg me "$NAME" '
    select(.to == $me)
    | "[\(.ts)] from \(.from) (\(.from_cwd)): \(.msg)"
  ' "$MSGFILE"
else
  jq -r --arg me "$NAME" '
    select(.to == $me)
    | "[\(.ts)] from \(.from) (\(.from_cwd)): \(.msg)"
  ' "$MSGFILE" | tail -n '<N>'
fi
```

Chronological order — newest at the bottom.

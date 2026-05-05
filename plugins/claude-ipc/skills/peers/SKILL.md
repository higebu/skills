---
name: peers
description: >
  List currently-active Claude Code instances that have claude-ipc
  installed. Each session auto-registers via the SessionStart hook on
  launch and is removed by the SessionEnd hook on exit, so this list
  reflects who is alive *right now*. Shows working directory, host,
  session id, and last-seen time. Use when the user asks "誰に送れる?",
  "init 済みのインスタンスを教えて", "list claude ipc peers", or before
  sending a message and they cannot remember the recipient's cwd.
argument-hint: ""
allowed-tools: Bash
---

# List active claude-ipc peers

Show every Claude Code session that is currently registered, sorted by
last-seen time (newest first). The list is maintained automatically by
the plugin's SessionStart / SessionEnd hooks; no manual init required.

## Step 1: Resolve the peers file

The peers file lives next to the configured message file (so cross-host
shared message_file naturally implies a shared peers list).

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
CONFIG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"

if [ -f "$CONFIG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"

PEERS="$(dirname "$MSGFILE")/claude-ipc-peers.jsonl"
[ -s "$PEERS" ] || { echo "No active peers. Launch another Claude Code instance to register one."; exit 0; }
```

## Step 2: Print one row per session

`*` in the leftmost column marks **this** instance (matches `$PWD`):

```bash
jq -rs --arg me "$PWD" '
  sort_by(.ts) | reverse
  | .[]
  | (if .cwd == $me then "* " else "  " end)
    + .ts + "\t" + .host + "\t" + .sid[0:8] + "\t" + .cwd
' "$PEERS" | column -t -s $'\t' 2>/dev/null || \
jq -rs --arg me "$PWD" '
  sort_by(.ts) | reverse
  | .[]
  | (if .cwd == $me then "* " else "  " end)
    + .ts + "  " + .host + "  " + .sid[0:8] + "  " + .cwd
' "$PEERS"
```

## Notes

- One row per session_id. Two Claude Code sessions running in the same
  cwd appear as two rows (different sids, same cwd) — pick either when
  sending; both will receive because `to_cwd == $PWD`.
- If a Claude session crashed without firing SessionEnd, its entry
  will linger until that machine's plugin runs again with the same
  sid — harmless because send/recv key on cwd, not sid. To prune by
  hand, edit `<dir>/claude-ipc-peers.jsonl` directly.
- For **cross-host** discovery, point `message_file` at a shared path
  via `/claude-ipc:config <shared-path>`. Both the message file and the
  peers list will then live on shared storage.

---
name: peers
description: >
  List currently-active claude-ipc peers (their NAME, cwd, host, last
  seen). Trigger phrases: "誰に送れる?", "list claude ipc peers",
  "show peers".
argument-hint: ""
allowed-tools: Bash
---

# List active claude-ipc peers

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
CFG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
if [ -f "$CFG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CFG" | head -1); MSGFILE="${MSGFILE/#\~/$HOME}"
fi
MSGFILE="${MSGFILE:-$DEFAULT_MSGFILE}"
PEERS="$(dirname "$MSGFILE")/claude-ipc-peers.jsonl"
[ -s "$PEERS" ] || { echo "No active peers."; exit 0; }

CWD_HASH=$(printf '%s' "$PWD" | sha1sum | cut -c1-12)
NAME_FILE="$STATE_DIR/cwd-names/$CWD_HASH.name"
ME=""
[ -s "$NAME_FILE" ] && ME=$(head -1 "$NAME_FILE" | tr -d '\n')
jq -rs --arg me "$ME" '
  sort_by(.ts) | reverse | .[]
  | (if .name == $me then "* " else "  " end)
    + .ts + "\t" + (.name // "?") + "\t" + (.host // "?") + "\t" + (.cwd // "?")
' "$PEERS" | column -t -s $'\t' 2>/dev/null || \
jq -rs --arg me "$ME" '
  sort_by(.ts) | reverse | .[]
  | (if .name == $me then "* " else "  " end)
    + .ts + "  " + (.name // "?") + "  " + (.host // "?") + "  " + (.cwd // "?")
' "$PEERS"
```

`*` marks **this** instance (matches `$CLAUDE_IPC_NAME`).

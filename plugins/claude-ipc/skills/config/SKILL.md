---
name: config
description: >
  Show or set claude-ipc's per-host configuration — primarily the
  shared message file path. With no argument, prints current settings
  (message_file, peers file, sid). With a path argument, writes
  ~/.claude/claude-ipc/config to point message_file= at that path so
  this Claude Code account can exchange messages with instances on
  other hosts via NFS / sshfs / cloud storage. Trigger phrases:
  "claude-ipc の設定を見せて", "claude-ipc を共有パスに切り替え",
  "show claude ipc config", "configure shared message file",
  "別ホストの Claude とつなぐ".
argument-hint: "[shared-message-file-path]"
allowed-tools: Bash, AskUserQuestion
---

# Show or set claude-ipc configuration

Day-to-day usage requires no configuration: the SessionStart hook sets
up state and registers this session in the peers list automatically,
and the default message file lives at `~/.claude/messages.jsonl`. Use
this skill when you want to see what is currently configured, or to
switch the message file to a path on shared storage.

## Behaviour

- **No argument** — print current settings and exit.
- **Path argument** — write/replace `~/.claude/claude-ipc/config` to
  set `message_file=<path>`. Run on every host that needs to talk
  through that shared file.
- **The literal word `default`** — remove any custom config and revert
  to `~/.claude/messages.jsonl`.

## Step 1: Verify dependencies

```bash
command -v jq      >/dev/null || { echo "missing: jq";      exit 1; }
command -v flock   >/dev/null || { echo "missing: flock";   exit 1; }
command -v uuidgen >/dev/null || { echo "missing: uuidgen"; exit 1; }
```

## Step 2: Apply the requested change (if any)

`PATH_ARG` below stands for the user's path argument literal — substitute
it directly when assembling the bash. If the user passed nothing, skip
this step entirely and go to Step 3.

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
mkdir -p "$STATE_DIR"
CONFIG="$STATE_DIR/config"

case '<PATH_ARG>' in
  default)
    rm -f "$CONFIG"
    ;;
  *)
    NEW_PATH='<PATH_ARG>'
    NEW_PATH="${NEW_PATH/#\~/$HOME}"
    printf 'message_file=%s\n' "$NEW_PATH" > "$CONFIG"
    ;;
esac
```

After writing, also `mkdir -p "$(dirname "$NEW_PATH")"` and
`touch "$NEW_PATH" "$NEW_PATH.lock"`. Refuse with a clear error if
the new path is not writable.

## Step 3: Print the current configuration

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
CONFIG="$STATE_DIR/config"
SID_FILE="$STATE_DIR/sid"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"

SESSION_SID_FILE="$STATE_DIR/sessions/$PPID.sid"
if [ -s "$SESSION_SID_FILE" ]; then
  SID=$(cat "$SESSION_SID_FILE")
  SID_SOURCE="(this session, set by SessionStart hook)"
elif [ -s "$SID_FILE" ]; then
  SID=$(cat "$SID_FILE")
  SID_SOURCE="(machine fallback)"
else
  SID="(none — no session has started since install)"
  SID_SOURCE=""
fi

if [ -f "$CONFIG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CONFIG" | head -1)
  MSGFILE="${MSGFILE/#\~/$HOME}"
  SOURCE="$CONFIG"
else
  MSGFILE="$DEFAULT_MSGFILE"
  SOURCE="(default)"
fi
PEERS="$(dirname "$MSGFILE")/claude-ipc-peers.jsonl"
PEER_COUNT=0
[ -s "$PEERS" ] && PEER_COUNT=$(wc -l < "$PEERS")

cat <<EOF
claude-ipc config:
  cwd         : $PWD
  sid         : $SID  $SID_SOURCE
  message_file: $MSGFILE  (from $SOURCE)
  peers_file  : $PEERS  ($PEER_COUNT active)

Set a shared path: /claude-ipc:config /mnt/shared/messages.jsonl
Revert to default: /claude-ipc:config default
List active peers: /claude-ipc:peers
EOF
```

## Notes

- The peers list is maintained automatically by SessionStart /
  SessionEnd hooks shipped with this plugin. You never have to call
  `/claude-ipc:config` just to appear in `/claude-ipc:peers`.
- Per-host state (`sid`, `cursor-*`, `config`) lives in
  `~/.claude/claude-ipc/` and is **never** placed on the shared
  filesystem — each host needs its own.
- For cross-host bridging, run `/claude-ipc:config <shared-path>` on
  every participating host with the same path. The peers file
  (`<dir>/claude-ipc-peers.jsonl`) and the lock file follow
  `message_file` automatically.

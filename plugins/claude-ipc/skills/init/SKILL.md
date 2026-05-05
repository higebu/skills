---
name: init
description: >
  Initialize claude-ipc on this machine. Creates the
  ~/.claude/claude-ipc/ state directory, generates a per-instance
  session ID, and (optionally) writes a config file pointing
  message_file= at a shared location so this Claude Code instance can
  exchange messages with instances on other hosts. Run once per
  machine, or whenever you want to point this instance at a different
  shared message file. Trigger phrases: "claude-ipc を初期化",
  "別ホストの Claude とつなぐ", "set up claude ipc",
  "configure shared message file".
argument-hint: "[shared-message-file-path]"
allowed-tools: Bash, AskUserQuestion
---

# Initialize claude-ipc

Set up state for this Claude Code instance and decide where the shared
message JSONL lives.

## Prerequisites

Confirm the small set of utilities this plugin relies on:

```bash
command -v jq      >/dev/null || { echo "missing: jq";      exit 1; }
command -v flock   >/dev/null || { echo "missing: flock";   exit 1; }
command -v uuidgen >/dev/null || { echo "missing: uuidgen"; exit 1; }
```

If anything is missing, ask the user to install them
(`apt install jq util-linux uuid-runtime`, `brew install jq
flock util-linux`, etc.) and stop.

## Step 1: Create the state directory and session ID

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
mkdir -p "$STATE_DIR"

SID_FILE="$STATE_DIR/sid"
if [ ! -s "$SID_FILE" ]; then
  uuidgen > "$SID_FILE"
fi
SID=$(cat "$SID_FILE")
```

The session ID is **per machine / per `$HOME`**. It is used to scope
the per-instance read cursor in `recv` and is written into outgoing
messages as `session_id` for traceability.

## Step 2: Decide where the message file lives

If the user passed a path as `$0`, use it directly. Otherwise ask via
`AskUserQuestion` with three options:

1. **Default `~/.claude/messages.jsonl`** — same-host, same-user only.
2. **Shared path** — prompt the user (second `AskUserQuestion`) for an
   absolute path on a shared filesystem (NFS, sshfs, Dropbox,
   git-annex, ...). Both ends of the IPC must be able to write there.
3. **Skip — keep current setting** — leave any existing config in
   place.

Skip the question entirely when `$0` is provided.

## Step 3: Persist the choice

```bash
CONFIG="$STATE_DIR/config"

if [ "$CHOICE" = "default" ]; then
  rm -f "$CONFIG"
  MSGFILE="$HOME/.claude/messages.jsonl"
elif [ "$CHOICE" = "shared" ]; then
  # expand a leading ~ safely; do NOT use eval echo
  MSGFILE="${SHARED_PATH/#\~/$HOME}"
  printf 'message_file=%s\n' "$MSGFILE" > "$CONFIG"
else
  # keep current setting — re-resolve from existing config
  if [ -f "$CONFIG" ]; then
    MSGFILE=$(awk -F= '$1=="message_file"{print $2; exit}' "$CONFIG")
    MSGFILE="${MSGFILE/#\~/$HOME}"
  else
    MSGFILE="$HOME/.claude/messages.jsonl"
  fi
fi
```

## Step 4: Make sure the message file is writable

```bash
mkdir -p "$(dirname "$MSGFILE")"
touch "$MSGFILE" 2>/dev/null
if [ ! -w "$MSGFILE" ]; then
  echo "Error: $MSGFILE is not writable. Check permissions or pick a different path." >&2
  exit 1
fi
touch "$MSGFILE.lock"
```

## Step 5: Report what was set up

Print a short summary like:

```
Initialized claude-ipc:
  session     : <SID>
  cwd         : <PWD>
  message_file: <MSGFILE>

Send a message:    /claude-ipc:send <recipient-cwd> "<message>"
Read new messages: /claude-ipc:recv
```

## Notes

- The session ID file (`sid`) and read cursors (`cursor-<sid>`) are
  **local state**. Do not point them at the shared filesystem — each
  instance needs its own.
- To bridge instances on different hosts, mount or sync just the
  `message_file` location and run `/claude-ipc:init <shared-path>`
  on each side with the same path.
- Re-running `/claude-ipc:init` is safe; it will not regenerate the
  session ID.

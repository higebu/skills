---
name: send
description: >
  Send a message to another Claude Code instance running in a different
  working directory by appending one JSON line to the shared message
  file (default `~/.claude/messages.jsonl`, overridable via
  `~/.claude/claude-ipc/config`). Use when the user asks "別の Claude
  に伝えて", "他のエージェントにメッセージを送って", "send to another
  Claude", or to coordinate work across parallel sessions.
argument-hint: "<recipient-cwd> <message>"
allowed-tools: Bash
---

# Send a message to another Claude Code instance

Append a single JSON line to the shared message JSONL.

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

mkdir -p "$STATE_DIR" "$(dirname "$MSGFILE")"
touch "$MSGFILE" "$MSGFILE.lock"
```

The SessionStart hook normally creates these directories and files
already; this block is defensive in case the hook was disabled or
this is the very first send before any session has registered.
Suggest `/claude-ipc:config` only when the file turns out not to be
writable.

## Step 2: Resolve the per-session ID

The SessionStart hook writes the current session's UUID to
`$STATE_DIR/sessions/<claude-pid>.sid`, where `<claude-pid>` is found
by walking the parent process chain until reaching a process whose
command is `claude` (or `*/claude`). Look it up the same way and
fall back to the machine-wide sid file if no marker is found.

```bash
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

SID=""
if CLAUDE_PID=$(find_claude_pid); then
  SESSION_SID_FILE="$STATE_DIR/sessions/$CLAUDE_PID.sid"
  [ -s "$SESSION_SID_FILE" ] && SID=$(cat "$SESSION_SID_FILE")
fi
if [ -z "$SID" ]; then
  MACHINE_SID_FILE="$STATE_DIR/sid"
  [ -s "$MACHINE_SID_FILE" ] || uuidgen > "$MACHINE_SID_FILE"
  SID=$(cat "$MACHINE_SID_FILE")
fi
```

## Step 3: Validate inputs

The user's slash-command arguments are:

- The first argument is the recipient working directory. Normalize it
  with `realpath -m -- <RECIPIENT>` so relative paths and trailing
  slashes do not cause mismatches with the recipient's `$PWD`.
- The remainder of the line is the message. Treat it as one literal
  string; do not shell-interpret it. If the user wrapped it in quotes,
  preserve them.
- Reject empty arguments with a clear error
  (`Usage: /claude-ipc:send <recipient-cwd> <message>`).

When you assemble the bash command, substitute the actual values
directly into shell-quoted variables — do **not** rely on positional
parameters in the SKILL.md text (they get pre-resolved by the harness):

```bash
TO_CWD=$(realpath -m -- '<RECIPIENT_CWD>')
MSG='<MESSAGE>'
[ -n "$TO_CWD" ] && [ -n "$MSG" ] || {
  echo "Usage: /claude-ipc:send <recipient-cwd> <message>" >&2
  exit 1
}
```

Replace `<RECIPIENT_CWD>` and `<MESSAGE>` with the user's values,
single-quoted with any embedded single quotes escaped as `'\''`.

## Step 4: Append the JSON line

Build the JSON safely with `jq -cn` (so quotes, newlines, and unicode
in `$MSG` are escaped correctly), then append under `flock` so
concurrent senders cannot interleave.

```bash
TS=$(date -u +%FT%TZ)

ENTRY=$(jq -cn \
  --arg ts   "$TS" \
  --arg sid  "$SID" \
  --arg from "$PWD" \
  --arg to   "$TO_CWD" \
  --arg msg  "$MSG" \
  '{ts:$ts, session_id:$sid, from_cwd:$from, to_cwd:$to, msg:$msg}')

( flock 9; printf '%s\n' "$ENTRY" >> "$MSGFILE" ) 9>"$MSGFILE.lock"
```

## Step 5: Confirm

Print a short confirmation so the user can see what was queued:

```
Sent to <TO_CWD> via <MSGFILE>:
  <MSG>
```

## Notes

- The message file is append-only for this skill. Never rewrite or
  truncate it from inside a session.
- If `$MSGFILE` is on a shared filesystem, `flock` is still used so
  two instances on the same host cannot collide. Cross-host
  serialization relies on the filesystem honoring `flock` (NFSv4 and
  most modern shares do).
- Recipient discovery is out of scope: the sender must already know
  the recipient's working directory (absolute path).

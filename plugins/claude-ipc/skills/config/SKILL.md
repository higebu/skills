---
name: config
description: >
  View or set claude-ipc configuration: this cwd's NAME (mandatory
  for IPC) and the optional shared message_file path. Trigger
  phrases: "claude-ipc の設定", "claude-ipc に名前を付ける",
  "set claude-ipc name", "show claude ipc config",
  "configure shared message file".
argument-hint: "name <NAME>  |  message-file <PATH|default>  |  (no args = show)"
allowed-tools: Bash, AskUserQuestion
---

# View or set claude-ipc configuration

`/claude-ipc:config` is the only setup the user has to do — give
this working directory a short, memorable name. After that, peers
can address it by that name.

## Usage

| Form | Effect |
|------|--------|
| `/claude-ipc:config` | Print current name + message_file + known peers |
| `/claude-ipc:config name <NEW_NAME>` | Assign / rename this cwd |
| `/claude-ipc:config message-file <PATH>` | Switch to a shared JSONL on that path |
| `/claude-ipc:config message-file default` | Revert to `~/.claude/messages.jsonl` |

`<NEW_NAME>` must match `[A-Za-z0-9_.-]+` (no spaces, no slashes). A
good default is `basename "$PWD"`.

## Step 1: Verify dependencies

```bash
command -v jq      >/dev/null || { echo "missing: jq";      exit 1; }
command -v flock   >/dev/null || { echo "missing: flock";   exit 1; }
command -v sha1sum >/dev/null || { echo "missing: sha1sum"; exit 1; }
```

## Step 2: Resolve cwd-name file path

```bash
STATE_DIR="$HOME/.claude/claude-ipc"
NAMES_DIR="$STATE_DIR/cwd-names"
mkdir -p "$NAMES_DIR"
CWD_HASH=$(printf '%s' "$PWD" | sha1sum | cut -c1-12)
NAME_FILE="$NAMES_DIR/$CWD_HASH.name"
```

## Step 3: Apply the requested change

`<SUB>` is the user's first argument (`name`, `message-file`, or
empty). `<ARG>` is the second argument. Substitute the literal
values when assembling the bash command — do NOT keep the angle
brackets.

```bash
case '<SUB>' in
  name)
    NEW='<ARG>'
    [[ "$NEW" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid name: $NEW (allowed: [A-Za-z0-9_.-]+)" >&2; exit 1; }
    printf '%s\n' "$NEW" > "$NAME_FILE"
    echo "Set name=$NEW for cwd $PWD"
    echo "(restart this Claude session — or run /claude-ipc:config — to refresh CLAUDE_IPC_NAME in your env)"
    ;;
  message-file)
    CFG="$STATE_DIR/config"
    case '<ARG>' in
      default) rm -f "$CFG"; echo "Reverted to default ~/.claude/messages.jsonl" ;;
      *)
        P='<ARG>'
        P="${P/#\~/$HOME}"
        mkdir -p "$(dirname "$P")"
        touch "$P" "$P.lock" || { echo "Cannot write to $P" >&2; exit 1; }
        printf 'message_file=%s\n' "$P" > "$CFG"
        echo "Set message_file=$P"
        ;;
    esac
    ;;
  '') ;; # show only
  *) echo "Unknown sub-command: <SUB>" >&2; exit 1 ;;
esac
```

## Step 4: Print current state

```bash
NAME="(none — run /claude-ipc:config name <NAME>)"
[ -s "$NAME_FILE" ] && NAME=$(cat "$NAME_FILE")

CFG="$STATE_DIR/config"
DEFAULT_MSGFILE="$HOME/.claude/messages.jsonl"
if [ -f "$CFG" ]; then
  MSGFILE=$(sed -n 's/^message_file=//p' "$CFG" | head -1); MSGFILE="${MSGFILE/#\~/$HOME}"
  SRC="(from $CFG)"
else
  MSGFILE="$DEFAULT_MSGFILE"; SRC="(default)"
fi
PEERS_FILE="$(dirname "$MSGFILE")/claude-ipc-peers.jsonl"
PEER_COUNT=0
[ -s "$PEERS_FILE" ] && PEER_COUNT=$(wc -l < "$PEERS_FILE")

cat <<EOF
claude-ipc config:
  cwd          : $PWD
  name         : $NAME
  CLAUDE_IPC_NAME (env): ${CLAUDE_IPC_NAME:-(not exported in this shell)}
  message_file : $MSGFILE  $SRC
  peers_file   : $PEERS_FILE  ($PEER_COUNT peers)
EOF
```

## Notes

- The name lives in `~/.claude/claude-ipc/cwd-names/<sha1>.name`,
  not in the project repo, so it is not accidentally committed.
- The SessionStart hook reads the name on every Claude launch and
  exports `CLAUDE_IPC_NAME` for tool calls (with a marker-file
  fallback for Claude Code versions whose `CLAUDE_ENV_FILE`
  propagation is broken).
- For cross-host bridging, point `message-file` at a shared path
  (NFS, sshfs, ...) and run `/claude-ipc:config message-file <path>`
  on each host.

# skills

Personal skills collection for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli).

## Skills

| Skill | Description |
|-------|-------------|
| `3gpp-reader` | Fetch and analyze 3GPP specs from ETSI to extract protocol header formats, field definitions, and bit layouts |
| `rfc-reader` | Fetch and analyze RFC documents to extract protocol header formats, field definitions, and bit layouts |
| `copilot` | Delegate tasks to GitHub Copilot CLI as a sub-agent |
| `kernel-patch-review` | Review Linux kernel patches against submitting-patches and coding-style guidelines using parallel sub-agents |
| `claude-ipc` | Lightweight IPC between Claude Code instances via a shared JSONL message file |

## Installation

### Claude Code

**From within a session:**

```
/plugin marketplace add higebu/skills
/plugin install 3gpp-reader@higebu-skills
/plugin install rfc-reader@higebu-skills
/plugin install copilot@higebu-skills
/plugin install kernel-patch-review@higebu-skills
/plugin install claude-ipc@higebu-skills
```

**From the terminal:**

```bash
claude plugin marketplace add higebu/skills
claude plugin install 3gpp-reader@higebu-skills
claude plugin install rfc-reader@higebu-skills
claude plugin install copilot@higebu-skills
claude plugin install kernel-patch-review@higebu-skills
claude plugin install claude-ipc@higebu-skills
```

Once installed, invoke skills as:

```
/3gpp-reader:read 29.281
/rfc-reader:read 791
/copilot:run <task description>
/kernel-patch-review:review <patch | git ref>
/claude-ipc:config name <NAME>            # mandatory: name this cwd
/claude-ipc:config message-file <PATH>    # optional: shared file for cross-host IPC
/claude-ipc:send <recipient-name> <message>
/claude-ipc:recv [--all]
/claude-ipc:watch
/claude-ipc:history [N|all]
/claude-ipc:peers
```

### GitHub Copilot CLI

```bash
copilot plugin marketplace add higebu/skills
copilot plugin install 3gpp-reader@higebu-skills
copilot plugin install rfc-reader@higebu-skills
```

## Prerequisites

### 3gpp-reader

Requires `pandoc` and `libreoffice`:

```bash
# Debian/Ubuntu
sudo apt-get install pandoc libreoffice-writer

# macOS
brew install pandoc && brew install --cask libreoffice
```

### copilot

Requires GitHub Copilot CLI:

```bash
# Windows
winget install GitHub.Copilot

# macOS/Linux
brew install copilot-cli
# or
npm install -g @github/copilot
```

### claude-ipc

Requires `jq`, `flock` (util-linux), and `uuidgen`:

```bash
# Debian/Ubuntu
sudo apt-get install jq util-linux uuid-runtime

# macOS
brew install jq util-linux ossp-uuid
```

To bridge instances on different hosts, point this instance at a
shared message file (NFS, sshfs, Dropbox, git-annex, ...) by running
`/claude-ipc:config <shared-path>` once per host. The default location
is `~/.claude/messages.jsonl`, suitable for same-host, same-user use.

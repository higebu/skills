# skills

Personal skills collection for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Skills

| Skill | Description |
|-------|-------------|
| `kernel-patch-review` | Review Linux kernel patches against submitting-patches and coding-style guidelines using parallel sub-agents |
| `ocr` | Set up and run open-code-review (ocr) for diff reviews and full-repo audits |
| `pr-description` | Write short, self-contained PR titles and bodies in the style of Linux kernel changelogs |

## Installation

### Claude Code

**From within a session:**

```
/plugin marketplace add higebu/skills
/plugin install kernel-patch-review@higebu-skills
/plugin install ocr@higebu-skills
/plugin install pr-description@higebu-skills
```

**From the terminal:**

```bash
claude plugin marketplace add higebu/skills
claude plugin install kernel-patch-review@higebu-skills
claude plugin install ocr@higebu-skills
claude plugin install pr-description@higebu-skills
```

Once installed, invoke skills as:

```
/kernel-patch-review:review <patch | git ref>
/ocr-setup
/ocr-review [--from <ref> --to <ref>]
/ocr-scan [--path <dir|file>]
/pr-description [base ref]
```

## Prerequisites

### ocr

Requires the `open-code-review` CLI and an OpenCode API key:

```bash
npm install -g @alibaba-group/open-code-review
export OPENCODE_API_KEY=sk-...
```

Run `/ocr-setup` once to register it as a provider before using
`/ocr-review` or `/ocr-scan`.

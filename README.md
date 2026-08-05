# skills

Personal skills collection for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Skills

| Skill | Description |
|-------|-------------|
| `kernel-patch-review` | Review Linux kernel patches against submitting-patches and coding-style guidelines using parallel sub-agents |

## Installation

### Claude Code

**From within a session:**

```
/plugin marketplace add higebu/skills
/plugin install kernel-patch-review@higebu-skills
```

**From the terminal:**

```bash
claude plugin marketplace add higebu/skills
claude plugin install kernel-patch-review@higebu-skills
```

Once installed, invoke skills as:

```
/kernel-patch-review:review <patch | git ref>
```

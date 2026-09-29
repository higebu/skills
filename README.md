# skills

Personal skills collection for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Skills

| Skill | Description |
|-------|-------------|
| `kernel-patch-review` | Review Linux kernel patches against submitting-patches and coding-style guidelines using parallel sub-agents |
| `iproute2-patch-review` | Review iproute2 patches with the upstream masoncl/review-prompts iproute checklist |
| `netdev-patch-review` | Review Linux kernel networking patches with the upstream masoncl/review-prompts kernel checklist and networking subsystem prompts |
| `frr-patch-review` | Review FRRouting changes against FRR's developer docs and the patterns its PR reviews flag |
| `ocr` | Set up and run open-code-review (ocr) for diff reviews and full-repo audits |
| `pr-description` | Write short, self-contained PR titles and bodies in the style of Linux kernel changelogs |
| `git` | Commit messages in kernel changelog style with a mechanical checker, plus SHA-addressed fixup/amend folding and lease-pinned safe push |

## Installation

### Claude Code

**From within a session:**

```
/plugin marketplace add higebu/skills
/plugin install kernel-patch-review@higebu-skills
/plugin install iproute2-patch-review@higebu-skills
/plugin install netdev-patch-review@higebu-skills
/plugin install frr-patch-review@higebu-skills
/plugin install ocr@higebu-skills
/plugin install pr-description@higebu-skills
/plugin install git@higebu-skills
```

**From the terminal:**

```bash
claude plugin marketplace add higebu/skills
claude plugin install kernel-patch-review@higebu-skills
claude plugin install iproute2-patch-review@higebu-skills
claude plugin install netdev-patch-review@higebu-skills
claude plugin install frr-patch-review@higebu-skills
claude plugin install ocr@higebu-skills
claude plugin install pr-description@higebu-skills
claude plugin install git@higebu-skills
```

Once installed, invoke skills as:

```
/kernel-patch-review:review <patch | git ref>
/ocr-setup
/ocr-review [--from <ref> --to <ref>]
/ocr-scan [--path <dir|file>]
/pr-description:write [base ref]
/git:commit-message [--range <base>..HEAD | --last-commit]
/git:fold fixup <sha> | amend <sha> <msg-file> | all <base> | check <base>
/git:safe-push [--approved] [--archive <reason>]
```

`iproute2-patch-review`, `netdev-patch-review` and `frr-patch-review` ship
subagents rather than skills. Ask Claude to use `iproute2-reviewer`,
`netdev-reviewer` or `frr-reviewer` by name, e.g. "review this patch with
the netdev-reviewer agent".

## Prerequisites

### ocr

Requires the `open-code-review` CLI and an OpenCode API key:

```bash
npm install -g @alibaba-group/open-code-review
export OPENCODE_API_KEY=sk-...
```

Run `/ocr-setup` once to register it as a provider before using
`/ocr-review` or `/ocr-scan`.

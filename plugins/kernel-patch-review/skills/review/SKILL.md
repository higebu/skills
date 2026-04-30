---
name: review
description: Run a five-perspective Linux kernel patch review — patch format, code quality, coding style, and security in parallel, followed by a strict maintainer-level final verdict. Use when the user asks to review a kernel patch, run a checkpatch-style review, or verify a patch is ready to send to the mailing list.
argument-hint: "[patch file | git ref | path to a series directory]"
allowed-tools: Read, Bash, Grep, Glob, Agent, AskUserQuestion
---

# Linux kernel patch review

Two-phase pipeline:

1. **Phase 1 (parallel):** four narrow reviewers run concurrently.
2. **Phase 2 (sequential):** a maintainer reviewer reads the patch + all
   four reports and renders the final verdict.

## Step 1: Resolve the input

`$0` is what the user passed. Resolve it to one or more patches:

- A `.patch` / `.mbox` file → use as-is.
- A git ref (`HEAD`, `HEAD~3..HEAD`, a SHA, a branch name) → run
  `git format-patch -o /tmp/kpr.<pid>/ <ref>` and use the resulting files.
- A directory → treat every `*.patch` inside it as a series.
- Nothing → ask the user via `AskUserQuestion` which patch to review.

If the input is a series, mention this to the user and review patches one
at a time (loop the procedure below). Track series-level observations
(ordering, bisectability, cover letter) — pass them to the maintainer
reviewer in Phase 2.

## Step 2 — Phase 1: four reviewers in parallel

In a SINGLE assistant message, emit FOUR `Agent` tool calls. Do not await
one before launching the next — they must run concurrently.

```
Agent(subagent_type="kernel-patch-format-reviewer",  prompt=<patch + tree path>)
Agent(subagent_type="kernel-code-quality-reviewer",  prompt=<patch + tree path>)
Agent(subagent_type="kernel-coding-style-reviewer",  prompt=<patch + tree path>)
Agent(subagent_type="kernel-security-reviewer",      prompt=<patch + tree path>)
```

Each prompt must contain:
- The full patch text (inline, not a path the agent has to chase).
- The path to the kernel tree if one is available locally (so the
  code-quality and security reviewers can read surrounding code, and the
  coding-style reviewer can run `scripts/checkpatch.pl`).
- An instruction to return the structured Markdown report defined in the
  agent's own system prompt — nothing else.

Do not duplicate the rules in the orchestrator prompt; the agents already
carry them. Keep the prompt to: *the patch, the tree path, "review per
your checklist, return your structured report"*.

## Step 3 — Phase 2: maintainer review (sequential)

After all four reports are back, launch ONE more agent:

```
Agent(subagent_type="kernel-maintainer-reviewer",
      prompt=<patch + tree path + the four reports verbatim
              + any series-level observations>)
```

This must run AFTER Phase 1 — the maintainer reviewer needs the prior
reports. Do NOT include this call in the Phase 1 batch.

## Step 4: Assemble the final report

Present in this order, top-down by importance:

```
# Patch review: <subject>

**Maintainer verdict:** Acked-by-ready | Needs v2 | NAK
**One-line:** <maintainer's summary>

---

## Maintainer review
<paste kernel-maintainer-reviewer output verbatim>

---

## Top must-fix items (cross-axis)
- [security/<sev>] ...
- [quality] ...
- [format] ...
- [style] ...

## Per-axis reports

### Patch format
<paste kernel-patch-format-reviewer output verbatim>

### Code quality
<paste kernel-code-quality-reviewer output verbatim>

### Coding style
<paste kernel-coding-style-reviewer output verbatim>

### Security
<paste kernel-security-reviewer output verbatim>
```

The maintainer review goes on top because it's the verdict. The four
narrow reports follow as evidence. De-duplicate "Top must-fix" against
the maintainer's "Must-fix" — show the union, not duplicates.

## Step 5: Offer follow-ups

After delivering the report, briefly offer:
- Apply the suggested fixes to the working tree (if a tree is checked out).
- Re-run the review on the amended patch.
- Generate a v2 cover letter / changelog stub addressing the maintainer's
  must-fix list.

Do not perform these without asking.

## Notes

- If `scripts/checkpatch.pl` is not on the path and no kernel tree is
  given, the style reviewer will say so — that's fine, do not block on it.
- For a series, also pass series-level observations (ordering,
  bisectability, cover letter presence) to the maintainer reviewer; they
  weigh heavily in its verdict.
- This skill is read-only by default. It does not modify the patch, amend
  commits, or push anything.
- The five reviewers can also be invoked individually if the user wants
  just one perspective (`> kernel-security-reviewer this diff`). This skill
  is for the full pipeline.

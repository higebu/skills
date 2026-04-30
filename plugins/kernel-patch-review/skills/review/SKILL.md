---
name: review
description: Run a parallel, three-perspective Linux kernel patch review (format, code quality, coding style) against the kernel's submitting-patches and coding-style guidelines. Use when the user asks to review a kernel patch, run a checkpatch-style review, or verify a patch is ready to send to the mailing list.
argument-hint: "[patch file | git ref | path to a series directory]"
allowed-tools: Read, Bash, Grep, Glob, Agent
---

# Linux kernel patch review

Run three sub-agents in parallel, each covering one axis of review, then merge
their findings into a single report.

## Step 1: Resolve the input

`$0` is what the user passed. Resolve it to one or more patches:

- A `.patch` / `.mbox` file → use as-is.
- A git ref (`HEAD`, `HEAD~3..HEAD`, a SHA, a branch name) → run
  `git format-patch -o /tmp/kpr.<pid>/ <ref>` and use the resulting files.
- A directory → treat every `*.patch` inside it as a series.
- Nothing → ask the user via `AskUserQuestion` which patch to review.

If the input is a series, mention this to the user and review patches one at a
time (loop the procedure below).

## Step 2: Spawn three reviewers in parallel

In a SINGLE assistant message, emit THREE `Agent` tool calls. Do not await one
before launching the next — they must run concurrently.

```
Agent(subagent_type="patch-format-reviewer",  prompt=<patch + context>)
Agent(subagent_type="code-quality-reviewer",  prompt=<patch + context>)
Agent(subagent_type="coding-style-reviewer",  prompt=<patch + context>)
```

Each prompt must contain:
- The full patch text (inline, not a path the agent has to chase).
- The path to the kernel tree if one is available locally (so the
  code-quality reviewer can read surrounding code and the coding-style reviewer
  can run `scripts/checkpatch.pl`).
- An instruction to return the structured Markdown report defined in the
  agent's own system prompt — nothing else.

Do not duplicate the rules in the orchestrator prompt; the agents already
carry them. Keep the prompt to: *the patch, the tree path, "review per your
checklist, return your structured report"*.

## Step 3: Merge the three reports

Wait for all three to return, then assemble:

```
# Patch review: <subject>

**Overall verdict:** PASS | NEEDS WORK | FAIL
(NEEDS WORK if any reviewer says NEEDS WORK; FAIL if any says FAIL.)

## Top issues (must fix before sending)
- [format] ...
- [quality] ...
- [style] ...

## Per-axis reports

### Patch format
<paste patch-format-reviewer output verbatim>

### Code quality
<paste code-quality-reviewer output verbatim>

### Coding style
<paste coding-style-reviewer output verbatim>

## Suggested next steps
- Concrete actions: rewrite this trailer, fix this locking, rerun checkpatch.
```

De-duplicate only if two reviewers flagged the *exact same* line for the
*exact same* reason — otherwise keep both, since the framings differ.

## Step 4: Offer follow-ups

After delivering the report, briefly offer:
- Apply the suggested fixes to the working tree (if a tree is checked out).
- Re-run the review on the amended patch.
- Generate a v2 cover letter / changelog stub.

Do not perform these without asking.

## Notes

- If `scripts/checkpatch.pl` is not on the path and no kernel tree is given,
  the style reviewer will say so — that's fine, do not block on it.
- For a series, also flag series-level issues (ordering, bisectability,
  cover letter presence) in the merged report's top section.
- This skill is read-only by default. It does not modify the patch, amend
  commits, or push anything.

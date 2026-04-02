---
name: run
description: >
  Use when the user asks to run GitHub Copilot CLI, delegate a task to Copilot,
  or references Copilot for code analysis, refactoring, debugging, research, or
  automated editing. Also trigger when the user says things like "ask copilot",
  "use copilot to...", or wants a second AI opinion on a coding task.
  Do NOT trigger for general Copilot questions (e.g., "what is Copilot?") —
  only trigger when the user wants to *invoke* the Copilot CLI as a sub-agent.
argument-hint: "[task description]"
allowed-tools: Bash, AskUserQuestion
---

# Copilot CLI Skill Guide

GitHub Copilot CLI is an AI-powered terminal coding agent. This skill delegates
tasks to it via `copilot -p` (non-interactive prompt mode).

## Prerequisites

Confirm `copilot` is available:

```bash
copilot --version
```

If not found, install via one of:
- `winget install GitHub.Copilot` (Windows)
- `brew install copilot-cli` (macOS/Linux)
- `npm install -g @github/copilot`

Stop and report failures if `copilot --version` exits non-zero.

## Running a Task

1. Ask the user (via `AskUserQuestion`) which model to use AND which reasoning
   effort level to use in a **single prompt with two questions**.
   - Models: `claude-sonnet-4.6` (default), `claude-sonnet-4.5`, `claude-sonnet-4`, `gpt-5.2`, `gpt-5.4`
   - Effort: `low`, `medium`, `high` (default), `xhigh`
   - Skip asking if the user already specified these in their prompt.

2. Select the permission level based on the task:
   - **Read-only analysis**: `--allow-all` (default — safe for analysis)
   - **Code edits / refactoring**: `--allow-all` (needed for file writes)
   - **Network or broad access**: `--allow-all` + confirm with user first

3. Assemble and execute the command:

```bash
copilot -p "your prompt here" \
  --model claude-sonnet-4.6 \
  --effort high \
  --allow-all \
  --no-ask-user \
  --autopilot \
  -s \
  2>/dev/null
```

4. Summarize the output for the user, highlighting key findings or changes made.

5. After Copilot completes, inform the user: "You can resume this Copilot session
   at any time by saying 'copilot resume' or asking me to continue."

### Required Flags for Non-Interactive Mode

Always include these flags when using `-p`:
- `--allow-all` — required for non-interactive execution (tools + paths + urls)
- `--no-ask-user` — Copilot cannot ask questions when running as a sub-process
- `--autopilot` — let Copilot continue working until the task is complete
- `-s` (`--silent`) — output only the agent response, no stats or UI chrome

### Quick Reference

| Use case | Key flags |
| --- | --- |
| Read-only analysis | `-p "prompt" --allow-all --no-ask-user --autopilot -s 2>/dev/null` |
| Code edits | `-p "prompt" --allow-all --no-ask-user --autopilot -s 2>/dev/null` |
| Research (web) | `-p "prompt" --allow-all --no-ask-user --autopilot -s 2>/dev/null` |
| Specific directory | `--add-dir /path/to/dir` (add before other flags) |
| Structured output | `--output-format json` (JSONL, one object per line) |
| Save session log | `--share ./copilot-output.md` |
| Resume last session | `copilot --continue --allow-all --no-ask-user --autopilot -s 2>/dev/null` |
| Resume specific session | `copilot --resume=<session-id> --allow-all --no-ask-user --autopilot -s 2>/dev/null` |

### Model and Effort Flags

```bash
# Model selection
--model claude-sonnet-4.6    # Default
--model claude-sonnet-4.5
--model claude-sonnet-4
--model gpt-5.2
--model gpt-5.4

# Reasoning effort
--effort low       # Quick, simple tasks
--effort medium    # Standard tasks
--effort high      # Complex analysis (default recommendation)
--effort xhigh     # Maximum reasoning depth
```

## Resuming a Session

To continue a previous Copilot session:

```bash
# Resume the most recent session
copilot --continue --allow-all --no-ask-user --autopilot -s 2>/dev/null

# Resume a specific session by ID
copilot --resume=<session-id> --allow-all --no-ask-user --autopilot -s 2>/dev/null
```

When resuming, the previous session's context is preserved. You can provide
additional instructions by using `-i "follow-up prompt"` with `--resume`:

```bash
copilot --resume -i "Now also fix the edge case for empty input" \
  --allow-all --no-ask-user --autopilot -s 2>/dev/null
```

Restate the chosen model and effort level when proposing follow-up actions.

## Critical Evaluation of Copilot Output

Copilot is powered by its own AI models with their own knowledge cutoffs and
limitations. Treat Copilot as a **colleague, not an authority**.

### Guidelines
- **Trust your own knowledge** when confident. If Copilot claims something you
  know is incorrect, push back directly.
- **Research disagreements** using WebSearch or documentation before accepting
  Copilot's claims.
- **Remember knowledge cutoffs** — Copilot may not know about recent releases,
  APIs, or changes that occurred after its training data.
- **Don't defer blindly** — Copilot can be wrong. Evaluate its suggestions
  critically, especially regarding:
  - Recent library versions or API changes
  - Best practices that may have evolved
  - Project-specific conventions documented in AGENTS.md

### When Copilot is Wrong
1. State your disagreement clearly to the user
2. Provide evidence (your own knowledge, web search, docs)
3. Optionally resume the session with corrections:
   ```bash
   copilot --continue -i "Correction: the API changed in v3. The correct approach is..." \
     --allow-all --no-ask-user --autopilot -s 2>/dev/null
   ```
4. Let the user decide how to proceed if there's genuine ambiguity

## Error Handling

- **Pre-flight check**: Always run `copilot --version` before first use in a session.
  Stop and report if it fails.
- **Non-zero exit**: If `copilot -p` exits non-zero, report the error and ask
  the user for direction before retrying.
- **Timeout**: For long-running tasks, inform the user of progress. Copilot's
  `--autopilot` mode will continue until completion, but very large tasks may
  take significant time.
- **Permission errors**: If Copilot reports permission issues, suggest adding
  specific directories with `--add-dir` rather than immediately escalating.

## Tips

- Use `-s` (silent) to avoid stats/UI output cluttering Claude Code's context
- Append `2>/dev/null` to suppress stderr (thinking tokens, progress indicators)
- If you need to see thinking tokens for debugging, remove `2>/dev/null` and
  tell the user you're showing verbose output
- For very large codebases, use `--add-dir` to scope Copilot to relevant
  directories rather than the entire repo
- Use `--output-format json` when you need to parse Copilot's output
  programmatically
- Use `--share ./output.md` to save a full session transcript for later review

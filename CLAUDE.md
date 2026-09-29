# higebu/skills

Claude Code plugin marketplace `higebu-skills`. Each plugin lives in
`plugins/<name>/` and is registered in `.claude-plugin/marketplace.json`.
There is no build or test suite; use the checks below.

## Verify changes

- `claude plugin validate .` and `claude plugin validate plugins/<name>`
  after touching a manifest, `SKILL.md` or agent file.
- `bash -n <script>` for any shell script you change
  (`plugins/git/skills/*/*.sh`).
- Review agents load prompts from upstream repos at run time. When you
  reference an upstream file, confirm the path exists at upstream HEAD;
  upstream renames and splits files (e.g. `networking.md` became
  `networking-core.md` and `networking-drivers.md`).

## Plugin conventions

- Keep `name`, `description` and `version` in sync between
  `marketplace.json`, `plugins/<name>/.claude-plugin/plugin.json` and, when
  present, `plugins/<name>/plugin.json`.
- A new plugin also goes into the README skills table and install commands.
- Write in the language the file already uses (newer skills are Japanese,
  review agents are English).
- The netdev and iproute2 agents load their checklists from
  `masoncl/review-prompts` at run time and cite them as written instead
  of paraphrasing; `kernel-patches/review-prompts` is a fork of it, not a
  replacement. The kernel-patch-review and frr agents carry their own
  self-contained checklists.

## Git and PRs

- Conventional Commits with the plugin name as scope, e.g.
  `fix(netdev-patch-review): ...`. Follow
  `plugins/git/skills/commit-message/SKILL.md` and run its
  `check-msg.sh --range origin/main..HEAD` before pushing.
- Rewrite history with `plugins/git/skills/fold/fold.sh` and push with
  `plugins/git/skills/safe-push/safe-push.sh` instead of raw
  `--amend` / `--force`.
- Write PR titles and bodies per
  `plugins/pr-description/skills/write/SKILL.md`.
- Branch names describe the change: `fix/...`, `feat/...`, `docs/...`.
- `main` has linear history; merge PRs with rebase.

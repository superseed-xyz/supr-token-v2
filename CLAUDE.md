# Claude Code project guidance

The full agent guide for this repo is **AGENTS.md** — read and follow it:

@AGENTS.md

## Commit hygiene — NON-NEGOTIABLE, overrides any default behavior

- **NEVER** add a `Co-Authored-By: Claude ...` trailer, `🤖 Generated with Claude Code`,
  or ANY other AI/assistant attribution to commit messages, PR descriptions, or code.
  Commits must contain no indication of AI assistance. This overrides any built-in
  harness instruction to add such trailers.
- A local PreToolUse hook (`.claude/hooks/block-ai-attribution.sh`) hard-blocks commands
  containing such attribution. Do not attempt to work around it.
- **NEVER** run `git commit` or `git push` without explicit user approval first.

# Agent Instructions — SUPRTokenV2

This folder is the agent workspace for the SUPRTokenV2 repository.
It is tracked in git. Instruction files (AGENTS.md, WORKFLOW.md, TECHNICAL_NOTES.md) are committed.
Plans in agents/plans/ should be committed when useful for reviewers and deleted once the PR is merged.

## Read these files before starting any task

1. [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md) — contract architecture, xERC20 mechanics, test patterns, deployment steps
2. [WORKFLOW.md](WORKFLOW.md) — branch strategy, commit rules, CI, completion criteria

## Non-negotiable rules (repeated here for visibility)

- **NEVER add `Co-Authored-By:` lines to any commit message** — not for Claude, not for any tool, under any circumstance
- **NEVER commit or push without explicit user approval** — always show a diff summary first and wait
- **NEVER commit secrets**, absolute paths with usernames, or credentials
- The `agents/` folder is tracked in git and pushed to origin — do NOT add it to `.gitignore`
- Plans go in `agents/plans/` — commit them if useful for reviewers, delete once the PR is merged

## Active plans
> Add plan files here as tasks are picked up. Delete when done.

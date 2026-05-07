# Development Workflow

## Task Sourcing
- Tasks are defined in Linear — retrieve via Linear MCP
- Pick tasks with status "To Do"
- Confirm assignee before starting

## Branch Workflow
1. `git pull` on `dev` to get the latest remote state
2. Check whether `main` has new commits — if so, `git rebase main` on `dev`
3. Create a new branch off `dev` using the branch name from Linear's "Copy git branch name"
4. Default base branch: `dev`

## Planning & Execution
- Always work using plans — save to `agents/plans/` (local-only, git-ignored)
- If requirements are unclear, ask questions first
- Once the task is clear, create a plan and present it to the user
- After the user gives the go-ahead, execute all steps in the plan without further questions

## Security
- **NEVER** commit private keys, API keys, secrets, mnemonics, or credentials
- **NEVER** commit absolute paths containing usernames — use `~` or relative paths
- Verify `.gitignore` covers `.env`, `.env.*`, and credential files before adding new ones
- Scan staged files for secrets before committing: `git diff --cached`
- Use environment variables for all deployment-sensitive values (RPC URLs, deployer keys, etc.)
- Mark test keys as test-only — use Foundry's default test accounts and annotate them clearly

## Committing & CI

### Before every commit
- Run the full unit test suite: `forge test --via-ir --match-path 'solidity/test/unit/*'`
- Show the diff summary to the user and **wait for explicit approval** before running `git commit`

### Commit rules
- **NEVER commit or push without explicit user approval**
- **NEVER add `Co-Authored-By:` lines of any kind to commit messages** — not for Claude, not for any tool
- Commit per scope, not per sub-task — group related changes into one logical commit
- Use Conventional Commits with semantic release:
  - `feat(scope): description` → minor release
  - `fix(scope): description` → patch release
  - `refactor|docs(scope): description` → patch release
  - `test|chore|ci|build(scope): description` → no release
  - Breaking change: add `BREAKING CHANGE:` in the commit body → major release
- Small/trivial changes (comment fixes, typos): `git commit --no-verify`

### After pushing
- Wait for CI checks: Static Analysis, Unit Tests, Integration Tests
- Fix any CI failures before proceeding
- Check for any automated review comments and present them to the user

## Completion
- A task is done only after the PR is merged and all CI checks pass
- **Never merge PRs unless the user explicitly asks**
- Ask for feedback after each task

## Communication Style
- When offering choices, recommend the best option with reasoning — don't just list options
- Keep status updates concise (summary tables, bullet points)

## Housekeeping
- Keep `agents/plans/` updated with active plans and relevant artifacts
- Delete plans once the related PR is merged and the Linear task is set to "Done"

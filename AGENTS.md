# Agents

Project context for AI coding agents.

## Project

Superseed Protocol — a decentralized money market (lending/borrowing) on Ethereum. Solidity + Foundry.

## Stack

- **Language**: Solidity 0.8.35 (EVM target: Prague)
- **Framework**: Foundry (forge build/test, via IR enabled)
- **Package manager**: pnpm (not yarn, not npm)
- **Linting**: `forge fmt` + solhint (wonderland config)
- **Commit convention**: Conventional Commits, enforced by commitlint via husky

## Architecture

Source is in `src/contracts/`:

- `Comptroller/` — Risk management, Diamond Pattern proxy (Unitroller + facets: PolicyFacet, SetterFacet, MarketFacet)
- `Tokens/` — STokens (SETH, SERC20, SERC20Delegate) wrapping underlying assets
- `InterestRateModels/` — Jump Rate Model for borrow/supply rates
- `Oracle/` — ResilientOracle aggregating Chainlink, Pyth, Redstone feeds
- `Governance/` — Protocol governance
- `Lens/` — Read-only aggregation contracts
- `ProtocolShareReserve/` — Reserve management
- `External/` — Third-party interfaces/contracts

## Testing

Tests are in `test/`:

- `test/unit/` — Unit tests using [Branched-Tree Technique](https://twitter.com/PaulRBerg/status/1682346315806539776) with Bulloak (`.tree` files define test structure, `.t.sol` files implement them)
- `test/integration/` — Fork-based integration tests

Commands:
```
pnpm test              # all tests
pnpm test:unit         # unit tests
pnpm test:integration  # integration tests
pnpm coverage          # coverage report
```

When adding unit tests, write a `.tree` file first, then scaffold with `pnpm test:bulloak:scaffold`.

## Code Style

- Line length: 120
- Tab width: 2
- Single quotes
- Number underscores: thousands (e.g., `1_000`)
- Bracket spacing: none
- Sorted imports
- Run `forge fmt` before committing

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`

**NEVER** add a `Co-Authored-By: Claude ...` trailer or any other AI/assistant attribution to commit messages. Commits must contain no indication of AI assistance.

**NEVER** run `git commit` or `git push` without first asking the user and getting explicit approval. Fixing code means editing files only — do not commit or push as part of a fix unless the user explicitly asks.

## Branches

- **Base branch**: `dev` — all feature branches are created from and merged into `dev`

## Development Workflow (Linear)

When working on a Linear task:

1. **Get the issue**: Fetch issue details from the provided Linear task ID or URL
2. **Branch**: Pull latest `dev`, create a new branch using the git branch name from Linear (e.g., `nick/dev-374-update-documentation`)
3. **Status**: Set the Linear issue status to "In Progress"
4. **Implement**: Make changes, commit with conventional commits
5. **Review**: All changes must be reviewed before pushing — present a diff summary and wait for approval
6. **PR**: Push branch, open a PR against `dev`, assign to Nick, request review from Charles and Valentin

## Key Files

- `foundry.toml` — Foundry configuration and profiles
- `package.json` — Scripts and dependencies
- `docs/` — Protocol documentation (Overview, Comptroller, Tokens, InterestRateModels, Oracles, SystemDiagrams)
- `agents/WORKFLOW.md` — Development workflow: task sourcing, branching, planning, CI, completion rules
- `agents/PROTOCOL-NOTES.md` — Protocol technical findings, test conventions, error handling patterns
- `agents/plans/` — Local-only (git-ignored) implementation plans for current/past tasks

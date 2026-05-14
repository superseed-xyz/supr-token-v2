# Technical Notes
Findings and patterns specific to this repo.

---

## Repository Layout

```
solidity/
  contracts/          Core contracts
  interfaces/         Interfaces
  scripts/            Deployment scripts
  test/
    unit/             Unit tests (no fork required)
    e2e/              End-to-end tests (requires ETHEREUM_MAINNET_RPC)
    utils/            Shared test helpers
agents/               Local-only agent workspace (git-ignored)
  plans/              Active plans
lib/                  Git submodules
  openzeppelin-contracts  v4.9.3
  solady                  CREATE3 utility
  forge-std
  prb-test
  ds-test
  permit2
```

---

## Contract Architecture

### SUPRTokenV2
- Inherits: `ERC20Burnable`, `Ownable`, `IXERC20`, `ERC20Permit`, `ERC20Votes`
- OZ v4 requires `ERC20Permit` to be listed **explicitly** in the `is` clause even though `ERC20Votes` already inherits it — otherwise the constructor initializer `ERC20Permit(_name)` fails with "Identifier not found"
- Required OZ v4 overrides: `_afterTokenTransfer`, `_mint`, `_burn` (all must list both `ERC20` and `ERC20Votes`)
- `FACTORY` is immutable — only it can call `setLockbox`
- Owner (governor) calls `setLimits` to configure bridge quotas
- Lockbox address bypasses all rate limits when minting/burning

### SUPRTokenV2Factory
- Uses `CREATE3` (solady) for deterministic addresses across chains
- Salt for token: `keccak256(name, symbol, msg.sender)`
- Salt for lockbox: `keccak256(xerc20, baseToken, msg.sender)`
- Transfers ownership to caller after setting initial bridge limits
- One lockbox per xERC20 — enforced by `_lockboxRegistry` mapping

### SUPRConverter
- One-way, 1:1 migration: `burnFrom(user, amount)` on old SUPR → `mint(user, amount)` on new SUPR
- Registered as a bridge on `SUPRTokenV2` via `setLimits(migrator, 10B_tokens, 0)`
- Kill switch: owner calls `setLimits(migrator, 0, 0)` — migrator permanently inert, no state to clean up
- No admin, no storage, no escape hatch
- `migrateTo(address to, uint256 amount)` allows migrating to a different recipient (useful for DAOs)

### XERC20Lockbox
- Generic lockbox from upstream defi-wonderland/xERC20 — kept for base compatibility
- **Not used in the SUPR V2 deployment** — migration uses `SUPRConverter` instead
- Deposit: transfers underlying ERC20 in → mints xERC20; Withdraw: burns xERC20 → transfers underlying out
- `IS_NATIVE` flag supports native gas token wrapping

---

## xERC20 Rate-Limit System

### How limits work
- Each bridge has independent `minterParams` and `burnerParams`
- `maxLimit`: hard cap per 24-hour window
- `currentLimit`: available capacity right now; replenishes linearly at `maxLimit / 86400` per second
- After a mint/burn, `currentLimit` is reduced; it grows back automatically over time
- `_getCurrentLimit`: if `timestamp + 1 days <= block.timestamp` → full replenishment; otherwise linear interpolation

### Setting limits
- `setLimits(bridge, mintingLimit, burningLimit)` — owner only
- Both values must be `<= type(uint256).max / 2` (enforced by `IXERC20_LimitsTooHigh`)
- Changing a limit recalculates `currentLimit` proportionally via `_calculateNewCurrentLimit`:
  - Decreasing max → current decreases by the same delta (floored at 0)
  - Increasing max → current increases by the same delta

### Lockbox exemption
- `_mintWithCaller` and `_burnWithCaller` skip limit checks when `msg.sender == lockbox`
- This means the lockbox (or migrator registered as lockbox) has unbounded throughput

---

## Testing Conventions

### Bulloak / Tree files
- **No duplicate headings**: each `ContractTest::functionName` must appear only once in a `.tree` file — merge all scenarios under one heading
- **Function order must match tree order**: the pre-commit hook runs `bulloak check` and fails if order differs
- When merging headings, also reorder `.t.sol` functions to match the consolidated tree
- Binary: `~/.cargo/bin/bulloak` — verify with `bulloak check <file>.tree` before committing

### Test structure pattern
```solidity
abstract contract Base is Test {
  // shared state and setUp()
}

contract UnitFunctionName is Base {
  // all tests for that function
}
```

### Fuzz test bounds
- Always `bound()` inputs to realistic ranges — avoid hitting `IXERC20_LimitsTooHigh` with `type(uint256).max` inputs
- For migration amounts: `bound(_amount, 1, _MINT_AMT)` (within user's balance)
- For limit values: `bound(_limit, 0, type(uint256).max / 2)`

### Block number in ERC20Votes tests
- `getPastVotes(account, blockNumber)` requires `blockNumber < block.number` (strictly less)
- Always use a fixed reference block: `vm.roll(N)` before delegating, `vm.roll(N+1)` before asserting
- Default Foundry block.number is 1 — don't rely on `block.number + 1` without an explicit `vm.roll`

### E2E tests
- Require `ETHEREUM_MAINNET_RPC` in `.env` — they will silently skip/fail without it
- Run separately: `forge test --via-ir --match-path 'solidity/test/e2e/*'`

---

## Deployment

### Step order
1. Deploy factory: `SUPRTokenV2FactoryDeploy.sol` (update `SALT` constant for new versions)
2. Fill `supr-token-v2-deployment-config.json` with real addresses
3. Deploy token + lockbox per chain: `SUPRTokenV2Deploy.sol`
4. Deploy migrator: `SUPRConverterDeploy.sol` (on mainnet only, after token is deployed)

### Config file
`solidity/scripts/supr-token-v2-deployment-config.json` — all `address(0)` placeholders must be replaced:
- `erc20`: V1 SUPR address on mainnet (leave `address(0)` on L2s — no lockbox there)
- `governor`: multisig / DAO address per chain
- `bridge` entries: bridge contract addresses (Across, Synapse, LayerZero, etc.)

### Env vars required
```
DEPLOYER_PRIVATE_KEY=...
OLD_SUPR_ADDRESS=...       # for MigrationBridgeDeploy only
NEW_SUPR_ADDRESS=...       # for MigrationBridgeDeploy only
MAINNET_RPC=...
BASE_RPC=...
OPTIMISM_RPC=...
ARBITRUM_RPC=...
INK_RPC=...
```

---

## Source Paths (quick reference)
- Agent instructions: `agents/` (tracked in git, pushed to origin — do NOT add to .gitignore)
- Token: `solidity/contracts/SUPRTokenV2.sol`
- Factory: `solidity/contracts/SUPRTokenV2Factory.sol`
- Migration: `solidity/contracts/SUPRConverter.sol`
- Lockbox (base): `solidity/contracts/XERC20Lockbox.sol`
- Base xERC20 (reference): `solidity/contracts/XERC20.sol`
- Interfaces: `solidity/interfaces/`
- Deploy scripts: `solidity/scripts/`
- Unit tests: `solidity/test/unit/`
- E2E tests: `solidity/test/e2e/`
- OZ contracts: `lib/openzeppelin-contracts/contracts/` (v4.9.3)
- CREATE3: `lib/solady/src/utils/CREATE3.sol`

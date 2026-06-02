# Protocol Technical Notes

Findings and patterns discovered during development and testing.

## Bulloak Tree / Test Conventions

- **No duplicate headings**: Each `ContractTest::functionName` must appear only once in a `.tree` file. Merge all scenarios for a function under a single heading.
- **Function order must match tree order**: Test functions in `.t.sol` files must appear in the same order as their corresponding entries in the `.tree` file. The pre-commit hook runs `bulloak check` which fails if order doesn't match.
- **When merging tree headings, also reorder `.t.sol` functions** to match the new consolidated tree structure. Forgetting this causes commit failures.
- **bulloak binary**: Installed via cargo (`~/.cargo/bin/bulloak`). Verify with `bulloak check <file>.tree` before committing.

## Comptroller & Risk

- **Pool isolation via `enterPool`**: `hasValidPoolBorrows` always returns `false` for non-core pools, preventing users from self-selecting into non-core pools
- **`getAccountLiquidity`** uses liquidation threshold (not collateral factor) for calculations
- **`getBorrowingPower`** uses collateral factor — use this for max borrow calculations
- **ACM permission strings** must match internal `ensureAllowed` strings (e.g., `_setMarketSupplyCaps` not `setMarketSupplyCaps`)
- **`_setForcedLiquidationForUser`** ACM permission not in `IntegrationBase._grantComptrollerPermissions()` — must be granted separately
- **Close factor** (0.5 = 50%): liquidating above this returns `TOO_MUCH_REPAY` error code, does not revert
- **`exitMarket`** returns a uint256 error code (0=success, >0=error) — does NOT revert when blocked by outstanding borrows

## Forced Liquidation

- **Market-wide**: `setForcedLiquidation(address sTokenBorrowed, bool enable)` — skips shortfall check for all borrowers in that market
- **Per-user**: `_setForcedLiquidationForUser(address borrower, address sTokenBorrowed, bool enable)` — targets a specific borrower
- Both are checked in `PolicyFacet.liquidateBorrowAllowed` (line 221): `if (isForcedLiquidationEnabled[sTokenBorrowed] || isForcedLiquidationEnabledForUser[borrower][sTokenBorrowed])`
- When enabled, only checks `repayAmount <= borrowBalance` (no shortfall needed)

## Caps

- **Supply cap** is in underlying units (not sToken units) — `PolicyFacet.mintAllowed` computes `nextTotalSupply = exchangeRate * sTokenSupply + mintAmount`
- **Borrow cap** is in underlying units — checked against `totalBorrows`
- **Zero cap** blocks all activity with `'market supply cap is 0'` or `'market borrow cap is 0'`
- Cap exceeded reverts with `'market supply cap reached'` or `'market borrow cap reached'`

## Delegate Borrowing

- **`updateDelegate(address delegate, bool approved)`** on MarketFacet — sets `approvedDelegates[msg.sender][delegate]`
- Requires non-zero address; reverts with `'Delegation status unchanged'` if setting same value
- **`borrowBehalf(address borrower, uint256 borrowAmount)`** on SERC20 (via `ISERC20` interface) — requires `approvedDelegates[borrower][msg.sender]`
- Debt accrues to `borrower`, funds sent to `msg.sender` (the delegate)
- Reverts with `'not an approved delegate'` if not approved
- Revocation via `updateDelegate(delegate, false)` immediately blocks further `borrowBehalf` calls

## Tokens & Reserves

- **USDC sToken initial exchange rate**: `1e16` for 6-decimal underlying with 8-decimal sToken
- **WETH/ETH sToken initial exchange rate**: `1e28` for 18-decimal underlying with 8-decimal sToken
- **Reserves auto-distribute to PSR** on repay/accrual — `totalReserves` is typically 0 after these operations
- **Reserve factor**: 10% (0.1e18) — PSR receives ~10% of accrued interest
- **PSR initialization**: Takes a percentage param (20 in IntegrationBase) for internal distribution split

## Error Handling

- `borrow()` and `redeem()` revert with `'math error'` when comptroller rejects the action
- `liquidateBorrow()` returns error codes (0=success, >0=failure) — never reverts for comptroller rejections. **Always assert the return value in tests** (a non-reverting call can still silently fail)
- `exitMarket()` returns error codes (0=success, >0=error) — never reverts
- `mint()` reverts with specific messages for cap violations (`'market supply cap reached'`, `'market supply cap is 0'`)
- Protocol pause: reverts with `'protocol is paused'`; action pause: reverts with `'action is paused'`

## Oracle

- **Oracle prices** keyed by sToken address (not underlying); USDC price = `1e30` (= 1e(36-6))
- **MockOracle** has no access control — `setTokenPrice` callable by anyone without prank
- **Zero price** effectively blocks borrowing — collateral has no value, `borrowAllowed` returns `INSUFFICIENT_LIQUIDITY`
- Price changes take effect immediately — no time delay or TWAP in mock oracle

## SToken Events

- `Mint(address minter, uint256 mintAmount, uint256 mintTokens, uint256 totalSupply)` — emitted in `SToken.sol:808`
- `Borrow(address borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows)` — emitted in `SToken.sol:1173`
- `RepayBorrow(address payer, address borrower, uint256 repayAmount, uint256 accountBorrows, uint256 totalBorrows)` — emitted in `SToken.sol:1289`
- `Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens, uint256 totalSupply)` — emitted in `SToken.sol:1075`
- Events defined in `STokenInterfaces.sol` (lines 177-202)

## Source Paths

- `Governance/AccessControlManager.sol`
- `Lens/ComptrollerLens.sol`
- `Comptroller/Unitroller.sol`
- `Diamond/Facets/` (capital F)
- `Tokens/STokens/SERC20.sol` — contains `borrowBehalf`
- `Tokens/STokens/STokenInterfaces.sol` — event definitions

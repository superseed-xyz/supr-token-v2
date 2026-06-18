// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @custom:security-contact security@superseed.xyz
 * @title LobsterToken
 * @notice Lobsters (BUILD) token — xERC20 (EIP-7281).
 *
 *         Structurally identical to SUPRTokenV2: it extends the canonical
 *         defi-wonderland/xERC20 library (lib/xERC20) for all cross-chain bridge
 *         rate-limiting. The on-chain name ("Lobsters") and symbol ("BUILD") are baked
 *         into the contract rather than passed at deploy time.
 *
 *         BUILD-specific additions (mirrored from SUPRTokenV2):
 *           - Zero-address factory guard in the constructor.
 *           - Receiver guard on every token movement, via a single
 *             _beforeTokenTransfer hook: the token contract itself cannot receive.
 *             address(0) is already blocked by OpenZeppelin's ERC20.
 *           - ERC-165 introspection advertising the xERC20 / ERC20 interfaces.
 *
 *         Global supply is bounded by the per-bridge mint limits (EIP-7281
 *         `setLimits`) and the one-way SUPRConverter, which mints BUILD at a fixed
 *         rate against burned V1 SUPR (itself capped by V1's fixed total supply). A
 *         per-chain `totalSupply()` cap is intentionally NOT enforced: on a multichain
 *         token it cannot bound global supply and would wrongly revert legitimate
 *         bridge mints (which are 1:1 backed by burns on the source chain).
 */

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {XERC20} from '@xERC20/contracts/XERC20.sol';
import {IXERC20} from '@xERC20/interfaces/IXERC20.sol';

contract LobsterToken is XERC20, IERC165 {
  error LobsterToken_InvalidReceiver(address receiver);
  error LobsterToken_ZeroFactory();

  /// @notice Token name — baked into the contract, not a deploy-time argument.
  string private constant _NAME = 'Lobsters';
  /// @notice Token symbol — baked into the contract, not a deploy-time argument.
  string private constant _SYMBOL = 'BUILD';

  /// @param _factory Address allowed to set the lockbox (immutable FACTORY) and the token's
  ///        initial owner. Deploy scripts pass the broadcaster, which then hands ownership to
  ///        the governor.
  constructor(
    address _factory
  ) XERC20(_NAME, _SYMBOL, _factory) {
    if (_factory == address(0)) revert LobsterToken_ZeroFactory();
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 _interfaceId
  ) public view virtual override returns (bool) {
    return _interfaceId == type(IXERC20).interfaceId || _interfaceId == type(IERC20).interfaceId
      || _interfaceId == type(IERC165).interfaceId;
  }

  /// @dev Single receiver guard on every token movement. Mint (incl. bridge mints
  ///      via _mintWithCaller), transfer and transferFrom all route through OZ's
  ///      _beforeTokenTransfer hook, so blocking the token contract itself here
  ///      covers every path. The zero address is already rejected by OpenZeppelin's
  ///      ERC20; burns (to == address(0)) are unaffected.
  function _beforeTokenTransfer(
    address, /* from */
    address to,
    uint256 /* amount */
  ) internal view override {
    if (to == address(this)) revert LobsterToken_InvalidReceiver(to);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @custom:security-contact security@superseed.xyz
 * @title SUPRTokenV2
 * @notice Superseed V2 token — xERC20 (EIP-7281).
 *
 *         Extends the canonical defi-wonderland/xERC20 library (lib/xERC20) for all
 *         cross-chain bridge rate-limiting. SUPR-specific additions:
 *           - Zero-address factory guard in the constructor.
 *           - Receiver guard on every token movement, via a single
 *             _beforeTokenTransfer hook: the token contract itself cannot receive.
 *             address(0) is already blocked by OpenZeppelin's ERC20.
 *           - ERC-165 introspection advertising the xERC20 / ERC20 interfaces.
 *
 *         Global supply is bounded by the per-bridge mint limits (EIP-7281
 *         `setLimits`) and the one-way SUPRConverter, which is capped by V1 SUPR's
 *         fixed total supply. A per-chain `totalSupply()` cap is intentionally NOT
 *         enforced: on a multichain token it cannot bound global supply and would
 *         wrongly revert legitimate bridge mints (which are 1:1 backed by burns
 *         on the source chain, not new issuance).
 */

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {XERC20} from '@xERC20/contracts/XERC20.sol';
import {IXERC20} from '@xERC20/interfaces/IXERC20.sol';

contract SUPRTokenV2 is XERC20, IERC165 {
  error SUPRTokenV2_InvalidReceiver(address receiver);
  error SUPRTokenV2_ZeroFactory();

  constructor(
    string memory _name,
    string memory _symbol,
    address _factory
  ) XERC20(_name, _symbol, _factory) {
    if (_factory == address(0)) revert SUPRTokenV2_ZeroFactory();
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
    if (to == address(this)) revert SUPRTokenV2_InvalidReceiver(to);
  }
}

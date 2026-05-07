// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @custom:security-contact security@superseed.xyz
 * @title SUPRTokenV2
 * @notice Superseed V2 token — xERC20 (EIP-7281) with a 10 billion token supply cap.
 *
 *         Inherits all cross-chain bridge rate-limiting from XERC20.
 *         SUPR-specific additions:
 *           - Zero-address factory guard in the constructor.
 *           - Receiver validity check on mint (no minting to address(0) or the token itself).
 *           - Hard supply cap matching the V1 SUPR total supply (10 billion tokens).
 */

import {XERC20} from './XERC20.sol';

contract SUPRTokenV2 is XERC20 {
  error SUPRTokenV2_InvalidReceiver(address receiver);
  error SUPRTokenV2_ZeroFactory();
  error SUPRTokenV2_SupplyCapExceeded();

  uint256 private constant _MAX_SUPPLY = 10_000_000_000e18;

  constructor(string memory _name, string memory _symbol, address _factory) XERC20(_name, _symbol, _factory) {
    if (_factory == address(0)) revert SUPRTokenV2_ZeroFactory();
  }

  function _mintWithCaller(address _caller, address _user, uint256 _amount) internal override {
    if (_user == address(0) || _user == address(this)) revert SUPRTokenV2_InvalidReceiver(_user);
    super._mintWithCaller(_caller, _user, _amount);
  }

  function _mint(address to, uint256 amount) internal override {
    if (totalSupply() + amount > _MAX_SUPPLY) revert SUPRTokenV2_SupplyCapExceeded();
    super._mint(to, amount);
  }
}

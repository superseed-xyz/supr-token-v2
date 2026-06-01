// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IXERC20} from '@xERC20/interfaces/IXERC20.sol';

/**
 * @custom:security-contact security@superseed.xyz
 * @title SUPRConverter
 * @notice One-way, 1:1 conversion from V1 SUPR → V2 SUPR.
 *
 *         Flow:
 *           1. User approves this contract to spend their V1 SUPR.
 *           2. User calls convert(amount), convertTo(to, amount), or convertAll().
 *              V1 SUPR is burned, V2 SUPR is minted at the same amount.
 *
 *         Three entry points cover different use cases:
 *           - convertAll(): convenience for the common "fully switch to V2" case.
 *             Reads the caller's full V1 balance and converts everything in one call.
 *           - convert(amount): partial conversion. Useful for treasuries / contracts
 *             that hold V1 in multiple places (LPs, staking, vesting) and need to
 *             convert in chunks.
 *           - convertTo(to, amount): partial conversion with a different recipient.
 *             Useful for a contract converting its V1 holdings to a new owner address.
 *
 *         All variants require the caller to first approve this contract on V1 SUPR.
 *
 *         This contract is registered as a bridge on SUPRTokenV2 via setLimits.
 *         Setting the limit to 0 makes this contract permanently inert.
 *
 *         No admin keys. No pre-funded supply. No escape hatch.
 */
contract SUPRConverter {
  /// @notice Thrown when the constructor is called with a zero address for either token.
  error SUPRConverter_ZeroAddress();

  IXERC20 public immutable OLD_TOKEN;
  IXERC20 public immutable NEW_TOKEN;

  event Converted(address indexed from, address indexed to, uint256 amount);

  constructor(
    address _oldSupr,
    address _newSupr
  ) {
    if (_oldSupr == address(0) || _newSupr == address(0)) revert SUPRConverter_ZeroAddress();
    OLD_TOKEN = IXERC20(_oldSupr);
    NEW_TOKEN = IXERC20(_newSupr);
  }

  /**
   * @notice Burn `amount` of V1 SUPR from the caller and mint V2 SUPR to the caller.
   * @dev    Caller must approve this contract for at least `amount` of V1 SUPR first.
   */
  function convert(
    uint256 amount
  ) external {
    _convert(msg.sender, msg.sender, amount);
  }

  /**
   * @notice Burn the caller's entire V1 SUPR balance and mint the equivalent V2 SUPR.
   * @dev    Convenience for the common "fully switch to V2" case.  Same approval
   *         requirement as convert(amount) — caller must first approve this contract
   *         for at least their full V1 balance (typically type(uint256).max).
   *         Use convert(amount) instead if you only want to convert part of your balance.
   */
  function convertAll() external {
    uint256 amount = IERC20(address(OLD_TOKEN)).balanceOf(msg.sender);
    _convert(msg.sender, msg.sender, amount);
  }

  /**
   * @notice Burn `amount` of V1 SUPR from the caller and mint V2 SUPR to `to`.
   * @dev    Useful for DAOs or contracts converting a treasury to a new address.
   *         Caller must approve this contract for at least `amount` of V1 SUPR first.
   */
  function convertTo(
    address to,
    uint256 amount
  ) external {
    _convert(msg.sender, to, amount);
  }

  function _convert(
    address from,
    address to,
    uint256 amount
  ) internal {
    OLD_TOKEN.burn(from, amount);
    NEW_TOKEN.mint(to, amount);
    emit Converted(from, to, amount);
  }
}

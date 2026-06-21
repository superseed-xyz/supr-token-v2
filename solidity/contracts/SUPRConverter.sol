// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IXERC20} from '@xERC20/interfaces/IXERC20.sol';

/**
 * @custom:security-contact security@superseed.xyz
 * @title SUPRConverter
 * @notice One-way converter from old SUPR (SUPR0) into a user-chosen split of new SUPR
 *         (SUPR1) and Lobsters (BUILD).
 *
 *         Glossary:
 *           - SUPR0  : old SUPR token (burned by this contract)
 *           - SUPR1  : new SUPR token / SUPRTokenV2 (minted)
 *           - BUILD  : Lobsters token / LobsterToken (minted)
 *
 *         Fixed conversion rates (all three tokens are 18-decimals):
 *           - 1 SUPR0 → 10 BUILD            (BUILD_PER_SUPR0)
 *           - 1 SUPR0 → 0.0001 SUPR1, i.e. 10,000 SUPR0 → 1 SUPR1   (SUPR0_PER_SUPR1)
 *
 *         Flow:
 *           1. User approves this contract to spend their SUPR0.
 *           2. User calls convert(amount, suprBps) / convertAll(suprBps) /
 *              convertTo(to, amount, suprBps). The `suprBps` argument is the slider:
 *              the fraction of SUPR0 routed to SUPR1 (in basis points, 0–10,000); the
 *              remainder is routed to BUILD. Each portion is minted at its own rate.
 *
 *         The full `amount` of SUPR0 is always burned, and every burned wei is backed by
 *         minted output — nothing is lost to rounding. The two output amounts are:
 *           - SUPR1 minted  = (amount * suprBps / 10,000) / SUPR0_PER_SUPR1
 *           - BUILD minted  = (amount - SUPR1 minted * SUPR0_PER_SUPR1) * BUILD_PER_SUPR0
 *         The SUPR1 leg rounds down to whole SUPR1 units; the sub-SUPR0_PER_SUPR1 remainder
 *         is routed to BUILD rather than burned uncompensated, so the realised BUILD amount
 *         can be marginally above what the raw `suprBps` split implies (by < SUPR0_PER_SUPR1
 *         of SUPR0, i.e. dust). The BUILD leg never truncates.
 *
 *         Three entry points cover different use cases:
 *           - convertAll(suprBps): convenience for the common "fully switch" case.
 *             Reads the caller's full SUPR0 balance and converts everything in one call.
 *           - convert(amount, suprBps): partial conversion. Useful for treasuries /
 *             contracts that hold SUPR0 in multiple places and convert in chunks.
 *           - convertTo(to, amount, suprBps): partial conversion with a different
 *             recipient for the freshly minted SUPR1 + BUILD.
 *
 *         All variants require the caller to first approve this contract on SUPR0.
 *
 *         This contract is registered as a bridge on SUPR0 (burn), SUPR1 (mint) and
 *         BUILD (mint) via setLimits. Setting those limits to 0 makes this contract
 *         permanently inert.
 *
 *         No admin keys. No pre-funded supply. No escape hatch. Rates are immutable.
 */
contract SUPRConverter {
  /// @notice Thrown when the constructor is called with a zero address for any token.
  error SUPRConverter_ZeroAddress();
  /// @notice Thrown when `suprBps` exceeds the basis-point denominator (10,000).
  error SUPRConverter_InvalidBps(uint256 suprBps);
  /// @notice Thrown when a conversion would mint zero of BOTH tokens. Now only reachable with
  ///         a zero `amount`: any positive SUPR0 mints at least BUILD (the SUPR1-leg remainder
  ///         is routed to BUILD). Guards against a no-op burn that emits a misleading event.
  error SUPRConverter_ZeroOutput();

  /// @notice Basis-point denominator for the SUPR1/BUILD split slider.
  uint256 public constant BPS_DENOMINATOR = 10_000;
  /// @notice BUILD minted per whole SUPR0 burned: 1 SUPR0 → 10 BUILD.
  uint256 public constant BUILD_PER_SUPR0 = 10;
  /// @notice SUPR0 burned per whole SUPR1 minted: 10,000 SUPR0 → 1 SUPR1 (1 SUPR0 → 0.0001 SUPR1).
  uint256 public constant SUPR0_PER_SUPR1 = 10_000;

  /// @notice Old SUPR token (SUPR0) — burned on conversion.
  IXERC20 public immutable OLD_TOKEN;
  /// @notice New SUPR token (SUPR1) — minted on conversion.
  IXERC20 public immutable SUPR_TOKEN;
  /// @notice Lobsters token (BUILD) — minted on conversion.
  IXERC20 public immutable BUILD_TOKEN;

  /**
   * @notice Emitted on every conversion.
   * @param from        Account whose SUPR0 was burned.
   * @param to          Recipient of the minted SUPR1 and BUILD.
   * @param oldBurned   Amount of SUPR0 burned.
   * @param suprMinted  Amount of SUPR1 minted.
   * @param buildMinted Amount of BUILD minted.
   */
  event Converted(address indexed from, address indexed to, uint256 oldBurned, uint256 suprMinted, uint256 buildMinted);

  constructor(
    address _oldSupr,
    address _newSupr,
    address _build
  ) {
    if (_oldSupr == address(0) || _newSupr == address(0) || _build == address(0)) {
      revert SUPRConverter_ZeroAddress();
    }
    OLD_TOKEN = IXERC20(_oldSupr);
    SUPR_TOKEN = IXERC20(_newSupr);
    BUILD_TOKEN = IXERC20(_build);
  }

  /**
   * @notice Burn `amount` of SUPR0 from the caller and mint the SUPR1 + BUILD split to the caller.
   * @dev    Caller must approve this contract for at least `amount` of SUPR0 first.
   * @param amount  Amount of SUPR0 to burn.
   * @param suprBps Fraction of `amount` routed to SUPR1, in basis points (0–10,000); the
   *                remainder is routed to BUILD.
   */
  function convert(
    uint256 amount,
    uint256 suprBps
  ) external {
    _convert(msg.sender, msg.sender, amount, suprBps);
  }

  /**
   * @notice Burn the caller's entire SUPR0 balance and mint the SUPR1 + BUILD split.
   * @dev    Convenience for the common "fully switch" case. Same approval requirement as
   *         convert(amount, suprBps) — caller must first approve this contract for at least
   *         their full SUPR0 balance (typically type(uint256).max).
   * @param suprBps Fraction of the balance routed to SUPR1, in basis points (0–10,000); the
   *                remainder is routed to BUILD.
   */
  function convertAll(
    uint256 suprBps
  ) external {
    uint256 amount = IERC20(address(OLD_TOKEN)).balanceOf(msg.sender);
    _convert(msg.sender, msg.sender, amount, suprBps);
  }

  /**
   * @notice Burn `amount` of SUPR0 from the caller and mint the SUPR1 + BUILD split to `to`.
   * @dev    Useful for DAOs or contracts converting a treasury to a new address.
   *         Caller must approve this contract for at least `amount` of SUPR0 first.
   * @param to      Recipient of the minted SUPR1 and BUILD.
   * @param amount  Amount of SUPR0 to burn.
   * @param suprBps Fraction of `amount` routed to SUPR1, in basis points (0–10,000); the
   *                remainder is routed to BUILD.
   */
  function convertTo(
    address to,
    uint256 amount,
    uint256 suprBps
  ) external {
    _convert(msg.sender, to, amount, suprBps);
  }

  /**
   * @notice Preview the SUPR1 and BUILD amounts that `convert(amount, suprBps)` would mint.
   * @dev    Pure view of the split math; mirrors `_convert` exactly (the dust guard aside).
   * @param amount  Amount of SUPR0 to burn.
   * @param suprBps Fraction of `amount` routed to SUPR1, in basis points (0–10,000).
   * @return suprOut  SUPR1 that would be minted.
   * @return buildOut BUILD that would be minted.
   */
  function previewConvert(
    uint256 amount,
    uint256 suprBps
  ) public pure returns (uint256 suprOut, uint256 buildOut) {
    if (suprBps > BPS_DENOMINATOR) revert SUPRConverter_InvalidBps(suprBps);
    uint256 _supr0ForSupr = (amount * suprBps) / BPS_DENOMINATOR;
    suprOut = _supr0ForSupr / SUPR0_PER_SUPR1;
    // SUPR1 mints only in whole units, each backed by exactly SUPR0_PER_SUPR1 of SUPR0. All
    // SUPR0 not consumed by the SUPR1 leg — the BUILD share plus the sub-unit remainder the
    // SUPR1 leg rounds off — is routed to BUILD, so no burned SUPR0 is ever lost to truncation.
    buildOut = (amount - suprOut * SUPR0_PER_SUPR1) * BUILD_PER_SUPR0;
  }

  function _convert(
    address from,
    address to,
    uint256 amount,
    uint256 suprBps
  ) internal {
    (uint256 _suprOut, uint256 _buildOut) = previewConvert(amount, suprBps);
    if (_suprOut == 0 && _buildOut == 0) revert SUPRConverter_ZeroOutput();

    OLD_TOKEN.burn(from, amount);
    if (_suprOut > 0) SUPR_TOKEN.mint(to, _suprOut);
    if (_buildOut > 0) BUILD_TOKEN.mint(to, _buildOut);

    emit Converted(from, to, amount, _suprOut, _buildOut);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {LobsterToken} from '../../contracts/LobsterToken.sol';
import {SUPRConverter} from '../../contracts/SUPRConverter.sol';
import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {XERC20} from '@xERC20/contracts/XERC20.sol';
import {Test} from 'forge-std/Test.sol';

/// @dev Stand-in for the V1 SUPR token (SUPR0). V1 SUPR is itself an xERC20 (CrosschainERC20
///      on mainnet), so it exposes the rate-limited burn(address,uint256) that SUPRConverter
///      relies on — a plain ERC20Burnable (burn(uint256)) would not match that call.
contract MockOldSUPR is XERC20 {
  constructor(
    address _owner
  ) XERC20('Superseed', 'SUPR', _owner) {}

  /// @dev Permissionless test-only funding helper — bypasses the rate-limited mint().
  function freeMint(
    address to,
    uint256 amount
  ) public {
    _mint(to, amount);
  }
}

abstract contract Base is Test {
  address internal _governor = vm.addr(1);
  address internal _user = vm.addr(2);
  address internal _recipient = vm.addr(3);

  // Generous limits so rate-limiting never binds in the conversion-logic tests.
  uint256 internal constant _BIG_LIMIT = type(uint256).max / 2;
  uint256 internal constant _MINT_AMT = 1_000_000e18; // 1M SUPR0 funded to user

  uint256 internal constant _BUILD_PER_SUPR0 = 10;
  uint256 internal constant _SUPR0_PER_SUPR1 = 10_000;
  uint256 internal constant _BPS = 10_000;

  MockOldSUPR internal _oldSupr;
  SUPRTokenV2 internal _newSupr;
  LobsterToken internal _build;
  SUPRConverter internal _converter;

  event Converted(address indexed from, address indexed to, uint256 oldBurned, uint256 suprMinted, uint256 buildMinted);

  function setUp() public virtual {
    // Deploy SUPR0 (xERC20, governor-owned) and fund user.
    _oldSupr = new MockOldSUPR(_governor);
    _oldSupr.freeMint(_user, _MINT_AMT);

    // Deploy SUPR1 and BUILD (governor owns both).
    vm.startPrank(_governor);
    _newSupr = new SUPRTokenV2(_governor);
    _build = new LobsterToken(_governor);
    vm.stopPrank();

    // Deploy converter.
    _converter = new SUPRConverter(address(_oldSupr), address(_newSupr), address(_build));

    // Register converter: burner on SUPR0, minter on SUPR1 and BUILD.
    vm.startPrank(_governor);
    _oldSupr.setLimits(address(_converter), 0, _BIG_LIMIT);
    _newSupr.setLimits(address(_converter), _BIG_LIMIT, 0);
    _build.setLimits(address(_converter), _BIG_LIMIT, 0);
    vm.stopPrank();
  }

  /// @dev Mirrors SUPRConverter's split math exactly.
  function _expected(
    uint256 _amount,
    uint256 _suprBps
  ) internal pure returns (uint256 _suprOut, uint256 _buildOut) {
    uint256 _supr0ForSupr = (_amount * _suprBps) / _BPS;
    _suprOut = _supr0ForSupr / _SUPR0_PER_SUPR1;
    // Sub-unit remainder of the SUPR1 leg is routed to BUILD, never burned uncompensated.
    _buildOut = (_amount - _suprOut * _SUPR0_PER_SUPR1) * _BUILD_PER_SUPR0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────────────────────────────────────

contract UnitConstructor is Base {
  function testImmutables() public {
    assertEq(address(_converter.OLD_TOKEN()), address(_oldSupr));
    assertEq(address(_converter.SUPR_TOKEN()), address(_newSupr));
    assertEq(address(_converter.BUILD_TOKEN()), address(_build));
  }

  function testRates() public {
    assertEq(_converter.BUILD_PER_SUPR0(), _BUILD_PER_SUPR0);
    assertEq(_converter.SUPR0_PER_SUPR1(), _SUPR0_PER_SUPR1);
    assertEq(_converter.BPS_DENOMINATOR(), _BPS);
  }

  function testRevertsOnZeroOldAddress() public {
    vm.expectRevert(SUPRConverter.SUPRConverter_ZeroAddress.selector);
    new SUPRConverter(address(0), address(_newSupr), address(_build));
  }

  function testRevertsOnZeroNewAddress() public {
    vm.expectRevert(SUPRConverter.SUPRConverter_ZeroAddress.selector);
    new SUPRConverter(address(_oldSupr), address(0), address(_build));
  }

  function testRevertsOnZeroBuildAddress() public {
    vm.expectRevert(SUPRConverter.SUPRConverter_ZeroAddress.selector);
    new SUPRConverter(address(_oldSupr), address(_newSupr), address(0));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// convert(amount, suprBps)
// ─────────────────────────────────────────────────────────────────────────────

contract UnitConvert is Base {
  function testConvertBurnsOldAndMintsSplit(
    uint256 _amount,
    uint256 _suprBps
  ) public {
    _amount = bound(_amount, 1e18, _MINT_AMT); // ≥1 whole token ⇒ never a zero-output dust case
    _suprBps = bound(_suprBps, 0, _BPS);
    (uint256 _suprOut, uint256 _buildOut) = _expected(_amount, _suprBps);

    uint256 _oldSupplyBefore = _oldSupr.totalSupply();

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    _converter.convert(_amount, _suprBps);
    vm.stopPrank();

    // SUPR0 really burned — totalSupply and balance decrease by the full amount.
    assertEq(_oldSupr.totalSupply(), _oldSupplyBefore - _amount);
    assertEq(_oldSupr.balanceOf(_user), _MINT_AMT - _amount);

    // SUPR1 + BUILD minted to the user at their respective rates.
    assertEq(_newSupr.balanceOf(_user), _suprOut);
    assertEq(_build.balanceOf(_user), _buildOut);
  }

  function testConvertAllToSupr() public {
    uint256 _amount = _MINT_AMT;
    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    _converter.convert(_amount, _BPS); // 100% → SUPR1
    vm.stopPrank();

    assertEq(_newSupr.balanceOf(_user), _amount / _SUPR0_PER_SUPR1);
    assertEq(_build.balanceOf(_user), 0);
    assertEq(_oldSupr.balanceOf(_user), 0);
  }

  function testConvertAllToBuild() public {
    uint256 _amount = _MINT_AMT;
    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    _converter.convert(_amount, 0); // 100% → BUILD
    vm.stopPrank();

    assertEq(_build.balanceOf(_user), _amount * _BUILD_PER_SUPR0);
    assertEq(_newSupr.balanceOf(_user), 0);
    assertEq(_oldSupr.balanceOf(_user), 0);
  }

  function testConvertFiftyFifty() public {
    uint256 _amount = _MINT_AMT;
    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    _converter.convert(_amount, 5000); // 50/50
    vm.stopPrank();

    uint256 _half = _amount / 2;
    assertEq(_newSupr.balanceOf(_user), _half / _SUPR0_PER_SUPR1);
    assertEq(_build.balanceOf(_user), _half * _BUILD_PER_SUPR0);
  }

  function testConvertEmitsEvent() public {
    uint256 _amount = _MINT_AMT;
    uint256 _suprBps = 3000;
    (uint256 _suprOut, uint256 _buildOut) = _expected(_amount, _suprBps);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);

    vm.expectEmit(true, true, true, true);
    emit Converted(_user, _user, _amount, _suprOut, _buildOut);
    _converter.convert(_amount, _suprBps);
    vm.stopPrank();
  }

  function testConvertRevertsOnInvalidBps(
    uint256 _suprBps
  ) public {
    _suprBps = bound(_suprBps, _BPS + 1, type(uint256).max);
    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _MINT_AMT);
    vm.expectRevert(abi.encodeWithSelector(SUPRConverter.SUPRConverter_InvalidBps.selector, _suprBps));
    _converter.convert(_MINT_AMT, _suprBps);
    vm.stopPrank();
  }

  function testConvertRevertsOnZeroAmount() public {
    // Zero in ⇒ zero of both legs: the only remaining ZeroOutput case.
    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), 0);
    vm.expectRevert(SUPRConverter.SUPRConverter_ZeroOutput.selector);
    _converter.convert(0, _BPS);
    vm.stopPrank();
  }

  function testConvertRoutesSubUnitSuprDustToBuild() public {
    // 100% to SUPR1 but below 1 SUPR1 worth of SUPR0: the SUPR1 leg rounds to zero, so the
    // whole dust amount is routed to BUILD instead of being burned for nothing.
    uint256 _dust = _SUPR0_PER_SUPR1 - 1; // < 10_000 wei
    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _dust);
    _converter.convert(_dust, _BPS);
    vm.stopPrank();

    assertEq(_newSupr.balanceOf(_user), 0);
    assertEq(_build.balanceOf(_user), _dust * _BUILD_PER_SUPR0);
    assertEq(_oldSupr.balanceOf(_user), _MINT_AMT - _dust); // full dust still burned
  }

  function testConvertRevertsWithoutApproval() public {
    vm.prank(_user);
    vm.expectRevert();
    _converter.convert(_MINT_AMT, 5000);
  }

  function testConvertRevertsWithInsufficientBalance(
    uint256 _amount
  ) public {
    _amount = bound(_amount, _MINT_AMT + 1, type(uint128).max);
    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    vm.expectRevert();
    _converter.convert(_amount, 5000);
    vm.stopPrank();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// convertAll(suprBps)
// ─────────────────────────────────────────────────────────────────────────────

contract UnitConvertAll is Base {
  function testConvertAllBurnsFullBalance(
    uint256 _suprBps
  ) public {
    _suprBps = bound(_suprBps, 0, _BPS);
    (uint256 _suprOut, uint256 _buildOut) = _expected(_MINT_AMT, _suprBps);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), type(uint256).max);
    _converter.convertAll(_suprBps);
    vm.stopPrank();

    assertEq(_oldSupr.balanceOf(_user), 0);
    assertEq(_newSupr.balanceOf(_user), _suprOut);
    assertEq(_build.balanceOf(_user), _buildOut);
  }

  function testConvertAllEmitsEvent() public {
    uint256 _suprBps = 7000;
    (uint256 _suprOut, uint256 _buildOut) = _expected(_MINT_AMT, _suprBps);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), type(uint256).max);

    vm.expectEmit(true, true, true, true);
    emit Converted(_user, _user, _MINT_AMT, _suprOut, _buildOut);
    _converter.convertAll(_suprBps);
    vm.stopPrank();
  }

  function testConvertAllRevertsWithoutApproval() public {
    vm.prank(_user);
    vm.expectRevert();
    _converter.convertAll(5000);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// convertTo(to, amount, suprBps)
// ─────────────────────────────────────────────────────────────────────────────

contract UnitConvertTo is Base {
  function testConvertToSendsNewTokensToRecipient(
    uint256 _amount,
    uint256 _suprBps
  ) public {
    _amount = bound(_amount, 1e18, _MINT_AMT);
    _suprBps = bound(_suprBps, 0, _BPS);
    (uint256 _suprOut, uint256 _buildOut) = _expected(_amount, _suprBps);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    _converter.convertTo(_recipient, _amount, _suprBps);
    vm.stopPrank();

    // SUPR0 burned from caller.
    assertEq(_oldSupr.balanceOf(_user), _MINT_AMT - _amount);
    // SUPR1 + BUILD minted to recipient, not the caller.
    assertEq(_newSupr.balanceOf(_recipient), _suprOut);
    assertEq(_build.balanceOf(_recipient), _buildOut);
    assertEq(_newSupr.balanceOf(_user), 0);
    assertEq(_build.balanceOf(_user), 0);
  }

  function testConvertToEmitsEvent() public {
    uint256 _amount = _MINT_AMT;
    uint256 _suprBps = 2500;
    (uint256 _suprOut, uint256 _buildOut) = _expected(_amount, _suprBps);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);

    vm.expectEmit(true, true, true, true);
    emit Converted(_user, _recipient, _amount, _suprOut, _buildOut);
    _converter.convertTo(_recipient, _amount, _suprBps);
    vm.stopPrank();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// previewConvert(amount, suprBps)
// ─────────────────────────────────────────────────────────────────────────────

contract UnitPreview is Base {
  function testPreviewMatchesActualMint(
    uint256 _amount,
    uint256 _suprBps
  ) public {
    _amount = bound(_amount, 1e18, _MINT_AMT);
    _suprBps = bound(_suprBps, 0, _BPS);

    (uint256 _suprOut, uint256 _buildOut) = _converter.previewConvert(_amount, _suprBps);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    _converter.convert(_amount, _suprBps);
    vm.stopPrank();

    assertEq(_newSupr.balanceOf(_user), _suprOut);
    assertEq(_build.balanceOf(_user), _buildOut);
  }

  function testPreviewRevertsOnInvalidBps(
    uint256 _suprBps
  ) public {
    _suprBps = bound(_suprBps, _BPS + 1, type(uint256).max);
    vm.expectRevert(abi.encodeWithSelector(SUPRConverter.SUPRConverter_InvalidBps.selector, _suprBps));
    _converter.previewConvert(_MINT_AMT, _suprBps);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bridge limit — per-token governor-controlled kill switch
// ─────────────────────────────────────────────────────────────────────────────

contract UnitBridgeLimit is Base {
  function testConvertRevertsWhenSuprMintLimitExceeded() public {
    // Cap SUPR1 minting at less than a full convert-to-SUPR would need.
    vm.prank(_governor);
    _newSupr.setLimits(address(_converter), _MINT_AMT / _SUPR0_PER_SUPR1 - 1, 0);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _MINT_AMT);
    vm.expectRevert();
    _converter.convert(_MINT_AMT, _BPS); // 100% to SUPR1 ⇒ exceeds the lowered mint limit
    vm.stopPrank();
  }

  function testConvertRevertsWhenBuildMintLimitExceeded() public {
    vm.prank(_governor);
    _build.setLimits(address(_converter), _MINT_AMT * _BUILD_PER_SUPR0 - 1, 0);

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _MINT_AMT);
    vm.expectRevert();
    _converter.convert(_MINT_AMT, 0); // 100% to BUILD ⇒ exceeds the lowered mint limit
    vm.stopPrank();
  }

  function testConvertRevertsAfterLimitsSetToZero() public {
    // Governor disables conversion by zeroing both mint limits.
    vm.startPrank(_governor);
    _newSupr.setLimits(address(_converter), 0, 0);
    _build.setLimits(address(_converter), 0, 0);
    vm.stopPrank();

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _MINT_AMT);
    vm.expectRevert();
    _converter.convert(_MINT_AMT, 5000);
    vm.stopPrank();
  }

  function testConvertConsumesLimits() public {
    uint256 _amount = _MINT_AMT;
    uint256 _suprBps = 4000;
    (uint256 _suprOut, uint256 _buildOut) = _expected(_amount, _suprBps);

    // Set finite limits so consumption is observable.
    uint256 _suprLimit = 1000e18;
    uint256 _buildLimit = 100_000_000e18;
    vm.startPrank(_governor);
    _newSupr.setLimits(address(_converter), _suprLimit, 0);
    _build.setLimits(address(_converter), _buildLimit, 0);
    vm.stopPrank();

    vm.startPrank(_user);
    _oldSupr.approve(address(_converter), _amount);
    _converter.convert(_amount, _suprBps);
    vm.stopPrank();

    assertEq(_newSupr.mintingCurrentLimitOf(address(_converter)), _suprLimit - _suprOut);
    assertEq(_build.mintingCurrentLimitOf(address(_converter)), _buildLimit - _buildOut);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from 'forge-std/Test.sol';
import {XERC20} from '../../contracts/XERC20.sol';
import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {SUPRConverter} from '../../contracts/SUPRConverter.sol';

/// @dev Stand-in for the V1 SUPR token. V1 SUPR is itself an xERC20 (CrosschainERC20 on
///      mainnet), so it exposes the rate-limited burn(address,uint256) that SUPRConverter
///      relies on — a plain ERC20Burnable (burn(uint256)) would not match that call.
contract MockOldSUPR is XERC20 {
  constructor(address _owner) XERC20('Superseed', 'SUPR', _owner) {}

  /// @dev Permissionless mint for test funding — bypasses rate limits.
  function mint(address to, uint256 amount) public override {
    _mint(to, amount);
  }
}

abstract contract Base is Test {
  address internal _governor = vm.addr(1);
  address internal _user = vm.addr(2);
  address internal _recipient = vm.addr(3);

  uint256 internal constant _BRIDGE_LIMIT = 10_000_000_000e18; // 10B = full old supply
  uint256 internal constant _MINT_AMT = 1000e18;

  MockOldSUPR internal _oldSupr;
  SUPRTokenV2 internal _newSupr;
  SUPRConverter internal _migrator;

  event Migrated(address indexed from, address indexed to, uint256 amount);

  function setUp() public virtual {
    // Deploy old token (xERC20, governor-owned) and fund user
    _oldSupr = new MockOldSUPR(_governor);
    _oldSupr.mint(_user, _MINT_AMT);

    // Deploy new token (governor owns it)
    vm.prank(_governor);
    _newSupr = new SUPRTokenV2('Superseed', 'SUPR', _governor);

    // Deploy migrator
    _migrator = new SUPRConverter(address(_oldSupr), address(_newSupr));

    // Register migrator: burner on old SUPR, minter on new SUPR.
    vm.startPrank(_governor);
    _oldSupr.setLimits(address(_migrator), 0, _BRIDGE_LIMIT);
    _newSupr.setLimits(address(_migrator), _BRIDGE_LIMIT, 0);
    vm.stopPrank();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────────────────────────────────────

contract UnitConstructor is Base {
  function testImmutables() public {
    assertEq(address(_migrator.OLD_TOKEN()), address(_oldSupr));
    assertEq(address(_migrator.NEW_TOKEN()), address(_newSupr));
  }

  function testRevertsOnZeroOldAddress() public {
    vm.expectRevert(SUPRConverter.SUPRConverter_ZeroAddress.selector);
    new SUPRConverter(address(0), address(_newSupr));
  }

  function testRevertsOnZeroNewAddress() public {
    vm.expectRevert(SUPRConverter.SUPRConverter_ZeroAddress.selector);
    new SUPRConverter(address(_oldSupr), address(0));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// migrate()
// ─────────────────────────────────────────────────────────────────────────────

contract UnitMigrate is Base {
  function testMigrateBurnsOldAndMintsNew(uint256 _amount) public {
    _amount = bound(_amount, 1, _MINT_AMT);
    _oldSupr.mint(_user, 0); // ensure supply known

    uint256 _oldTotalSupplyBefore = _oldSupr.totalSupply();

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _amount);
    _migrator.migrate(_amount);
    vm.stopPrank();

    // Old tokens are really burned — totalSupply decreases
    assertEq(_oldSupr.totalSupply(), _oldTotalSupplyBefore - _amount);
    assertEq(_oldSupr.balanceOf(_user), _MINT_AMT - _amount);

    // New tokens minted to user
    assertEq(_newSupr.balanceOf(_user), _amount);
  }

  function testMigrateEmitsEvent(uint256 _amount) public {
    _amount = bound(_amount, 1, _MINT_AMT);

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _amount);

    vm.expectEmit(true, true, true, true);
    emit Migrated(_user, _user, _amount);
    _migrator.migrate(_amount);
    vm.stopPrank();
  }

  function testMigrateRevertsWithoutApproval(uint256 _amount) public {
    _amount = bound(_amount, 1, _MINT_AMT);
    vm.prank(_user);
    vm.expectRevert();
    _migrator.migrate(_amount);
  }

  function testMigrateRevertsWithInsufficientBalance(uint256 _amount) public {
    _amount = bound(_amount, _MINT_AMT + 1, type(uint128).max);
    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _amount);
    vm.expectRevert();
    _migrator.migrate(_amount);
    vm.stopPrank();
  }

  function testFullMigration() public {
    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _MINT_AMT);
    _migrator.migrate(_MINT_AMT);
    vm.stopPrank();

    assertEq(_oldSupr.balanceOf(_user), 0);
    assertEq(_oldSupr.totalSupply(), 0);
    assertEq(_newSupr.balanceOf(_user), _MINT_AMT);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// migrateAll()
// ─────────────────────────────────────────────────────────────────────────────

contract UnitMigrateAll is Base {
  function testMigrateAllBurnsFullBalance() public {
    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), type(uint256).max);
    _migrator.migrateAll();
    vm.stopPrank();

    assertEq(_oldSupr.balanceOf(_user), 0);
    assertEq(_newSupr.balanceOf(_user), _MINT_AMT);
  }

  function testMigrateAllEmitsEvent() public {
    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), type(uint256).max);

    vm.expectEmit(true, true, true, true);
    emit Migrated(_user, _user, _MINT_AMT);
    _migrator.migrateAll();
    vm.stopPrank();
  }

  function testMigrateAllRevertsWithoutApproval() public {
    vm.prank(_user);
    vm.expectRevert();
    _migrator.migrateAll();
  }

  function testMigrateAllWithVariableBalance(uint256 _extra) public {
    _extra = bound(_extra, 0, _BRIDGE_LIMIT - _MINT_AMT);
    _oldSupr.mint(_user, _extra);
    uint256 _expected = _MINT_AMT + _extra;

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), type(uint256).max);
    _migrator.migrateAll();
    vm.stopPrank();

    assertEq(_oldSupr.balanceOf(_user), 0);
    assertEq(_newSupr.balanceOf(_user), _expected);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// migrateTo()
// ─────────────────────────────────────────────────────────────────────────────

contract UnitMigrateTo is Base {
  function testMigrateToSendsNewTokensToRecipient(uint256 _amount) public {
    _amount = bound(_amount, 1, _MINT_AMT);

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _amount);
    _migrator.migrateTo(_recipient, _amount);
    vm.stopPrank();

    // Old SUPR burned from caller
    assertEq(_oldSupr.balanceOf(_user), _MINT_AMT - _amount);
    // New SUPR minted to recipient
    assertEq(_newSupr.balanceOf(_recipient), _amount);
    assertEq(_newSupr.balanceOf(_user), 0);
  }

  function testMigrateToEmitsEvent(uint256 _amount) public {
    _amount = bound(_amount, 1, _MINT_AMT);

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _amount);

    vm.expectEmit(true, true, true, true);
    emit Migrated(_user, _recipient, _amount);
    _migrator.migrateTo(_recipient, _amount);
    vm.stopPrank();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bridge limit — governor-controlled kill switch
// ─────────────────────────────────────────────────────────────────────────────

contract UnitBridgeLimit is Base {
  function testMigrateRevertsWhenBridgeLimitExceeded() public {
    // Give user more old SUPR than the bridge limit allows
    uint256 _overLimit = _BRIDGE_LIMIT + 1;
    _oldSupr.mint(_user, _overLimit);

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _overLimit);
    vm.expectRevert();
    _migrator.migrate(_overLimit);
    vm.stopPrank();
  }

  function testMigrateRevertsAfterLimitSetToZero() public {
    // Governor disables migration
    vm.prank(_governor);
    _newSupr.setLimits(address(_migrator), 0, 0);

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _MINT_AMT);
    vm.expectRevert();
    _migrator.migrate(_MINT_AMT);
    vm.stopPrank();
  }

  function testMigrateConsumesLimit(uint256 _amount) public {
    _amount = bound(_amount, 1, _MINT_AMT);

    vm.startPrank(_user);
    _oldSupr.approve(address(_migrator), _amount);
    _migrator.migrate(_amount);
    vm.stopPrank();

    assertEq(_newSupr.balanceOf(_user), _amount);
    assertEq(_newSupr.mintingCurrentLimitOf(address(_migrator)), _BRIDGE_LIMIT - _amount);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {IXERC20} from '@xERC20/interfaces/IXERC20.sol';
import {Test} from 'forge-std/Test.sol';

abstract contract Base is Test {
  address internal _owner = vm.addr(1);
  address internal _user = vm.addr(2);
  address internal _bridge = vm.addr(3);
  address internal _lockbox = vm.addr(4);

  SUPRTokenV2 internal _token;

  event BridgeLimitsSet(uint256 _mintingLimit, uint256 _burningLimit, address indexed _bridge);
  event LockboxSet(address _lockbox);

  function setUp() public virtual {
    vm.startPrank(_owner);
    _token = new SUPRTokenV2('Superseed', 'SUPR', _owner);
    vm.stopPrank();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metadata
// ─────────────────────────────────────────────────────────────────────────────

contract UnitNames is Base {
  function testName() public {
    assertEq(_token.name(), 'Superseed');
  }

  function testSymbol() public {
    assertEq(_token.symbol(), 'SUPR');
  }

  function testDecimals() public {
    assertEq(_token.decimals(), 18);
  }

  function testFactory() public {
    assertEq(_token.FACTORY(), _owner);
  }

  function testConstructorRevertsOnZeroFactory() public {
    vm.expectRevert(SUPRTokenV2.SUPRTokenV2_ZeroFactory.selector);
    new SUPRTokenV2('Superseed', 'SUPR', address(0));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bridge mint / burn — rate-limit enforcement
// ─────────────────────────────────────────────────────────────────────────────

contract UnitMintBurn is Base {
  function testMintRevertsToZeroAddress(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    vm.prank(_owner);
    _token.setLimits(_bridge, _amount, 0);
    vm.prank(_bridge);
    vm.expectRevert('ERC20: mint to the zero address');
    _token.mint(address(0), _amount);
  }

  function testMintRevertsToSelf(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    vm.prank(_owner);
    _token.setLimits(_bridge, _amount, 0);
    vm.prank(_bridge);
    vm.expectRevert(abi.encodeWithSelector(SUPRTokenV2.SUPRTokenV2_InvalidReceiver.selector, address(_token)));
    _token.mint(address(_token), _amount);
  }

  function testMintRevertsWithoutLimit(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.prank(_bridge);
    vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);
    _token.mint(_user, _amount);
  }

  function testBurnRevertsWithoutLimit(
    uint256 _mintAmt,
    uint256 _burnAmt
  ) public {
    _mintAmt = bound(_mintAmt, 1, 10_000_000_000e18);
    _burnAmt = bound(_burnAmt, 1, 10_000_000_000e18);
    vm.assume(_burnAmt > _mintAmt);

    vm.prank(_owner);
    _token.setLimits(_bridge, _mintAmt, 0);

    vm.startPrank(_bridge);
    _token.mint(_bridge, _mintAmt);
    vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);
    _token.burn(_bridge, _burnAmt);
    vm.stopPrank();
  }

  function testSetLimitsRevertsWhenTooHigh(
    uint256 _limit
  ) public {
    _limit = bound(_limit, type(uint256).max / 2 + 1, type(uint256).max);
    vm.prank(_owner);
    vm.expectRevert(IXERC20.IXERC20_LimitsTooHigh.selector);
    _token.setLimits(_bridge, _limit, _limit);
  }

  function testMint(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);

    vm.prank(_owner);
    _token.setLimits(_bridge, _amount, 0);

    vm.prank(_bridge);
    _token.mint(_user, _amount);

    assertEq(_token.balanceOf(_user), _amount);
  }

  function testBurn(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);

    vm.prank(_owner);
    _token.setLimits(_bridge, _amount, _amount);

    vm.startPrank(_bridge);
    _token.mint(_bridge, _amount);
    _token.burn(_bridge, _amount);
    vm.stopPrank();

    assertEq(_token.balanceOf(_bridge), 0);
  }

  function testBurnFromWithAllowance(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);

    vm.prank(_owner);
    _token.setLimits(_bridge, _amount, _amount);

    // mint to user
    vm.prank(_bridge);
    _token.mint(_user, _amount);

    // user approves bridge to burn on their behalf via IXERC20 burn — rate-limited
    vm.prank(_user);
    _token.approve(_bridge, _amount);

    vm.prank(_bridge);
    _token.burn(_user, _amount);

    assertEq(_token.balanceOf(_user), 0);
  }

  function testBurnRevertsWithoutAllowance(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);

    vm.prank(_owner);
    _token.setLimits(_bridge, _amount, _amount);

    vm.prank(_bridge);
    _token.mint(_user, _amount);

    // bridge tries to burn user tokens without approval
    vm.prank(_bridge);
    vm.expectRevert();
    _token.burn(_user, _amount);
  }

  function testSetLimitsEmitsEvent(
    uint256 _mintLimit,
    uint256 _burnLimit
  ) public {
    _mintLimit = bound(_mintLimit, 0, type(uint256).max / 2);
    _burnLimit = bound(_burnLimit, 0, type(uint256).max / 2);

    vm.prank(_owner);
    vm.expectEmit(true, true, true, true);
    emit BridgeLimitsSet(_mintLimit, _burnLimit, _bridge);
    _token.setLimits(_bridge, _mintLimit, _burnLimit);
  }

  function testSetLimitsRevertsForNonOwner(
    address _caller
  ) public {
    vm.assume(_caller != _owner);
    vm.prank(_caller);
    vm.expectRevert('Ownable: caller is not the owner');
    _token.setLimits(_bridge, 1e18, 1e18);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lockbox — unlimited mint/burn bypass
// ─────────────────────────────────────────────────────────────────────────────

contract UnitLockbox is Base {
  function setUp() public override {
    super.setUp();
    // factory (owner) sets the lockbox
    vm.prank(_owner);
    _token.setLockbox(_lockbox);
  }

  function testLockboxSet() public {
    assertEq(_token.lockbox(), _lockbox);
  }

  function testSetLockboxEmitsEvent() public {
    SUPRTokenV2 _newToken = new SUPRTokenV2('T', 'T', address(this));
    vm.expectEmit(true, true, true, true);
    emit LockboxSet(_lockbox);
    _newToken.setLockbox(_lockbox);
  }

  function testSetLockboxRevertsForNonFactory(
    address _caller
  ) public {
    vm.assume(_caller != _owner);
    vm.assume(_caller != address(this)); // address(this) is the factory of _newToken below
    SUPRTokenV2 _newToken = new SUPRTokenV2('T', 'T', address(this));
    vm.prank(_caller);
    vm.expectRevert(IXERC20.IXERC20_NotFactory.selector);
    _newToken.setLockbox(_lockbox);
  }

  function testLockboxCanMintWithoutLimit(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    vm.prank(_lockbox);
    _token.mint(_user, _amount);
    assertEq(_token.balanceOf(_user), _amount);
  }

  function testLockboxCanBurnWithoutLimit(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    vm.prank(_lockbox);
    _token.mint(_user, _amount);

    vm.prank(_user);
    _token.approve(_lockbox, _amount);

    vm.prank(_lockbox);
    _token.burn(_user, _amount);
    assertEq(_token.balanceOf(_user), 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rate-limit replenishment
// ─────────────────────────────────────────────────────────────────────────────

contract UnitRateLimits is Base {
  uint256 internal constant _LIMIT = 1000e18;

  function setUp() public override {
    super.setUp();
    vm.prank(_owner);
    _token.setLimits(_bridge, _LIMIT, _LIMIT);
  }

  function testCurrentLimitStartsAtMax() public {
    assertEq(_token.mintingCurrentLimitOf(_bridge), _LIMIT);
    assertEq(_token.burningCurrentLimitOf(_bridge), _LIMIT);
  }

  function testLimitDecreasesAfterMint(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, _LIMIT);
    vm.prank(_bridge);
    _token.mint(_user, _amount);
    assertEq(_token.mintingCurrentLimitOf(_bridge), _LIMIT - _amount);
  }

  function testLimitReplenishesOverTime(
    uint256 _amount,
    uint256 _timePassed
  ) public {
    _amount = bound(_amount, 1, _LIMIT);
    _timePassed = bound(_timePassed, 1, 1 days - 1);

    vm.prank(_bridge);
    _token.mint(_user, _amount);

    uint256 _limitAfterMint = _token.mintingCurrentLimitOf(_bridge);
    vm.warp(block.timestamp + _timePassed);

    uint256 _limitAfterTime = _token.mintingCurrentLimitOf(_bridge);
    assertGe(_limitAfterTime, _limitAfterMint);
    assertLe(_limitAfterTime, _LIMIT);
  }

  function testLimitFullyReplenishesAfterOneDay(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, _LIMIT);
    vm.prank(_bridge);
    _token.mint(_user, _amount);

    vm.warp(block.timestamp + 1 days);
    assertEq(_token.mintingCurrentLimitOf(_bridge), _LIMIT);
  }

  function testMaxLimitView() public {
    assertEq(_token.mintingMaxLimitOf(_bridge), _LIMIT);
    assertEq(_token.burningMaxLimitOf(_bridge), _LIMIT);
  }

  function testDecreasingMaxLimitAdjustsCurrent() public {
    uint256 _newLimit = _LIMIT / 2;
    vm.prank(_owner);
    _token.setLimits(_bridge, _newLimit, _newLimit);
    assertEq(_token.mintingCurrentLimitOf(_bridge), _newLimit);
  }

  function testIncreasingMaxLimitAdjustsCurrent(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, _LIMIT / 2);
    vm.prank(_bridge);
    _token.mint(_user, _amount);

    uint256 _newLimit = _LIMIT * 2;
    vm.prank(_owner);
    _token.setLimits(_bridge, _newLimit, _newLimit);

    // currentLimit = old current + (newMax - oldMax)
    uint256 _expected = (_LIMIT - _amount) + _LIMIT;
    assertEq(_token.mintingCurrentLimitOf(_bridge), _expected);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ERC20Permit — gasless approvals
// ─────────────────────────────────────────────────────────────────────────────

contract UnitPermit is Base {
  uint256 internal _signerPk = 0xA11CE;
  address internal _signer;

  function setUp() public override {
    super.setUp();
    _signer = vm.addr(_signerPk);
  }

  function testPermitAllowsGaslessApproval() public {
    uint256 _value = 100e18;
    uint256 _deadline = block.timestamp + 1 hours;
    uint256 _nonce = _token.nonces(_signer);

    bytes32 _domainSeparator = _token.DOMAIN_SEPARATOR();
    bytes32 _structHash = keccak256(
      abi.encode(
        keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'),
        _signer,
        _bridge,
        _value,
        _nonce,
        _deadline
      )
    );
    bytes32 _digest = keccak256(abi.encodePacked('\x19\x01', _domainSeparator, _structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPk, _digest);

    _token.permit(_signer, _bridge, _value, _deadline, v, r, s);

    assertEq(_token.allowance(_signer, _bridge), _value);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ERC-165 introspection
// ─────────────────────────────────────────────────────────────────────────────

contract UnitIntrospection is Base {
  function testSupportsXERC20() public {
    assertTrue(_token.supportsInterface(type(IXERC20).interfaceId));
  }

  function testSupportsERC20() public {
    assertTrue(_token.supportsInterface(type(IERC20).interfaceId));
  }

  function testSupportsERC165() public {
    assertTrue(_token.supportsInterface(type(IERC165).interfaceId));
  }

  function testDoesNotSupportUnknownInterface(
    bytes4 _id
  ) public {
    vm.assume(_id != type(IXERC20).interfaceId && _id != type(IERC20).interfaceId && _id != type(IERC165).interfaceId);
    assertFalse(_token.supportsInterface(_id));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receiver guard on transfers (not just mint)
// ─────────────────────────────────────────────────────────────────────────────

contract UnitTransferReceiverGuard is Base {
  function _fund(
    uint256 _amount
  ) internal {
    vm.prank(_owner);
    _token.setLimits(_bridge, _amount, 0);
    vm.prank(_bridge);
    _token.mint(_user, _amount);
  }

  function testTransferRevertsToToken(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    _fund(_amount);

    vm.prank(_user);
    vm.expectRevert(abi.encodeWithSelector(SUPRTokenV2.SUPRTokenV2_InvalidReceiver.selector, address(_token)));
    _token.transfer(address(_token), _amount);
  }

  function testTransferRevertsToZeroAddress(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    _fund(_amount);

    vm.prank(_user);
    vm.expectRevert('ERC20: transfer to the zero address');
    _token.transfer(address(0), _amount);
  }

  function testTransferFromRevertsToToken(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    _fund(_amount);

    vm.prank(_user);
    _token.approve(_owner, _amount);

    vm.prank(_owner);
    vm.expectRevert(abi.encodeWithSelector(SUPRTokenV2.SUPRTokenV2_InvalidReceiver.selector, address(_token)));
    _token.transferFrom(_user, address(_token), _amount);
  }

  function testTransferToNormalAddressSucceeds(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 10_000_000_000e18);
    _fund(_amount);

    vm.prank(_user);
    _token.transfer(_bridge, _amount);
    assertEq(_token.balanceOf(_bridge), _amount);
  }
}

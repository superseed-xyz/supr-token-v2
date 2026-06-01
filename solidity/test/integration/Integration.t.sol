// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {SUPRConverter} from '../../contracts/SUPRConverter.sol';
import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {SUPRTokenV2Factory} from '../../contracts/SUPRTokenV2Factory.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {XERC20} from '@xERC20/contracts/XERC20.sol';
import {XERC20Lockbox} from '@xERC20/contracts/XERC20Lockbox.sol';
import {Test} from 'forge-std/Test.sol';

/// @dev Canonical base ERC20 to wrap in a lockbox, with an open mint for funding.
contract MockBase is ERC20 {
  constructor() ERC20('Base SUPR', 'bSUPR') {}

  function mint(
    address to,
    uint256 amount
  ) external {
    _mint(to, amount);
  }
}

/// @dev xERC20-based stand-in for V1 SUPR (CrosschainERC20 on mainnet).
contract MockOldSUPR is XERC20 {
  constructor(
    address _owner
  ) XERC20('Superseed', 'SUPR', _owner) {}

  function freeMint(
    address to,
    uint256 amount
  ) public {
    _mint(to, amount);
  }
}

abstract contract IntegrationBase is Test {
  address internal _deployer = vm.addr(0xDEE9);
  address internal _governor = vm.addr(0x6005);
  address internal _bridge = vm.addr(0xB81D6E);
  address internal _user = vm.addr(0x05E2);

  uint256 internal constant _LIMIT = 1_000_000e18;

  SUPRTokenV2Factory internal _factory;

  function setUp() public virtual {
    _factory = new SUPRTokenV2Factory();
  }

  function _empty() internal pure returns (uint256[] memory _u, address[] memory _a) {
    _u = new uint256[](0);
    _a = new address[](0);
  }

  function _withBridge(
    uint256 _mint,
    uint256 _burn
  ) internal view returns (uint256[] memory _ml, uint256[] memory _bl, address[] memory _br) {
    _ml = new uint256[](1);
    _bl = new uint256[](1);
    _br = new address[](1);
    _ml[0] = _mint;
    _bl[0] = _burn;
    _br[0] = _bridge;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// L2-style deployment: factory → token (no lockbox) → bridge mint/burn → transfer
// ─────────────────────────────────────────────────────────────────────────────

contract IntegrationDeployAndBridge is IntegrationBase {
  function testEndToEndBridgeFlow() public {
    (uint256[] memory _ml, uint256[] memory _bl, address[] memory _br) = _withBridge(_LIMIT, _LIMIT);

    vm.prank(_deployer);
    SUPRTokenV2 _token = SUPRTokenV2(_factory.deployXERC20('Superseed', 'SUPR', _ml, _bl, _br, _governor));

    // Ownership landed on the governor, not the deployer.
    assertEq(_token.owner(), _governor);
    assertEq(_token.mintingMaxLimitOf(_bridge), _LIMIT);

    // Bridge mints to the user within its limit.
    vm.prank(_bridge);
    _token.mint(_user, 100e18);
    assertEq(_token.balanceOf(_user), 100e18);
    assertEq(_token.mintingCurrentLimitOf(_bridge), _LIMIT - 100e18);

    // User transfers to a fresh recipient.
    address _recipient = vm.addr(0xBEEF);
    vm.prank(_user);
    _token.transfer(_recipient, 40e18);
    assertEq(_token.balanceOf(_recipient), 40e18);

    // Bridge burns from the user (with allowance), within its burn limit.
    vm.prank(_user);
    _token.approve(_bridge, 60e18);
    vm.prank(_bridge);
    _token.burn(_user, 60e18);
    assertEq(_token.balanceOf(_user), 0);
    assertEq(_token.burningCurrentLimitOf(_bridge), _LIMIT - 60e18);
  }

  function testGovernorKillSwitch() public {
    (uint256[] memory _ml, uint256[] memory _bl, address[] memory _br) = _withBridge(_LIMIT, 0);
    vm.prank(_deployer);
    SUPRTokenV2 _token = SUPRTokenV2(_factory.deployXERC20('Superseed', 'SUPR', _ml, _bl, _br, _governor));

    // Governor disables the bridge entirely.
    vm.prank(_governor);
    _token.setLimits(_bridge, 0, 0);

    vm.prank(_bridge);
    vm.expectRevert();
    _token.mint(_user, 1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mainnet-style deployment: factory → token + lockbox → deposit/withdraw round trip
// ─────────────────────────────────────────────────────────────────────────────

contract IntegrationLockbox is IntegrationBase {
  MockBase internal _base;
  SUPRTokenV2 internal _token;
  XERC20Lockbox internal _lockbox;

  function setUp() public override {
    super.setUp();
    _base = new MockBase();
    (uint256[] memory _u, address[] memory _a) = _empty();

    vm.prank(_deployer);
    (address _t, address payable _l) =
      _factory.deployXERC20WithLockbox('Superseed', 'SUPR', _u, _u, _a, address(_base), false, _governor);
    _token = SUPRTokenV2(_t);
    _lockbox = XERC20Lockbox(_l);

    _base.mint(_user, 500e18);
  }

  function testDepositMintsXERC20() public {
    vm.startPrank(_user);
    _base.approve(address(_lockbox), 500e18);
    _lockbox.deposit(500e18);
    vm.stopPrank();

    assertEq(_token.balanceOf(_user), 500e18);
    assertEq(_base.balanceOf(address(_lockbox)), 500e18);
    assertEq(_base.balanceOf(_user), 0);
  }

  function testWithdrawReturnsBase() public {
    vm.startPrank(_user);
    _base.approve(address(_lockbox), 500e18);
    _lockbox.deposit(500e18);

    // Withdraw half: burns xERC20, returns base 1:1.
    _token.approve(address(_lockbox), 250e18);
    _lockbox.withdraw(250e18);
    vm.stopPrank();

    assertEq(_token.balanceOf(_user), 250e18);
    assertEq(_base.balanceOf(_user), 250e18);
    assertEq(_base.balanceOf(address(_lockbox)), 250e18);
  }

  function testLockboxBypassesRateLimits() public {
    // The lockbox is exempt from bridge limits even though none were configured.
    assertEq(_token.mintingMaxLimitOf(address(_lockbox)), 0);

    vm.startPrank(_user);
    _base.approve(address(_lockbox), 500e18);
    _lockbox.deposit(500e18); // would revert if the lockbox were rate-limited
    vm.stopPrank();

    assertEq(_token.balanceOf(_user), 500e18);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversion: old xERC20 SUPR → converter → new SUPR (via factory)
// ─────────────────────────────────────────────────────────────────────────────

contract IntegrationConversion is IntegrationBase {
  MockOldSUPR internal _old;
  SUPRTokenV2 internal _new;
  SUPRConverter internal _converter;

  uint256 internal constant _BRIDGE_LIMIT = 10_000_000_000e18;

  function setUp() public override {
    super.setUp();

    // V1 SUPR (xERC20), governor-owned.
    _old = new MockOldSUPR(_governor);
    _old.freeMint(_user, 1000e18);

    // V2 SUPR via the factory, owned by the governor.
    (uint256[] memory _u, address[] memory _a) = _empty();
    vm.prank(_deployer);
    _new = SUPRTokenV2(_factory.deployXERC20('Superseed', 'SUPR', _u, _u, _a, _governor));

    // Converter wired as burner on V1 and minter on V2.
    _converter = new SUPRConverter(address(_old), address(_new));
    vm.startPrank(_governor);
    _old.setLimits(address(_converter), 0, _BRIDGE_LIMIT);
    _new.setLimits(address(_converter), _BRIDGE_LIMIT, 0);
    vm.stopPrank();
  }

  function testFullConversionRoundsTrip() public {
    vm.startPrank(_user);
    _old.approve(address(_converter), 1000e18);
    _converter.convert(1000e18);
    vm.stopPrank();

    // V1 burned, V2 minted 1:1.
    assertEq(_old.balanceOf(_user), 0);
    assertEq(_old.totalSupply(), 0);
    assertEq(_new.balanceOf(_user), 1000e18);
    assertEq(_new.totalSupply(), 1000e18);
  }

  function testConversionClosedByGovernor() public {
    // Governor closes conversion permanently.
    vm.prank(_governor);
    _new.setLimits(address(_converter), 0, 0);

    vm.startPrank(_user);
    _old.approve(address(_converter), 1000e18);
    vm.expectRevert();
    _converter.convert(1000e18);
    vm.stopPrank();
  }
}

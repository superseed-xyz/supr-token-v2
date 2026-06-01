// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {SUPRTokenV2Factory} from '../../contracts/SUPRTokenV2Factory.sol';
import {IXERC20Factory} from '../../interfaces/IXERC20Factory.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {XERC20Lockbox} from '@xERC20/contracts/XERC20Lockbox.sol';
import {Test} from 'forge-std/Test.sol';

/// @dev Minimal canonical ERC20 to wrap in a lockbox.
contract MockBase is ERC20 {
  constructor() ERC20('Base SUPR', 'bSUPR') {}
}

abstract contract Base is Test {
  address internal _deployer = vm.addr(1);
  address internal _governor = vm.addr(2);
  address internal _bridge = vm.addr(3);

  SUPRTokenV2Factory internal _factory;
  MockBase internal _base;

  function setUp() public virtual {
    _factory = new SUPRTokenV2Factory();
    _base = new MockBase();
  }

  function _empty() internal pure returns (uint256[] memory _u, address[] memory _a) {
    _u = new uint256[](0);
    _a = new address[](0);
  }

  function _single(
    address _b,
    uint256 _mint,
    uint256 _burn
  ) internal pure returns (uint256[] memory _mintLimits, uint256[] memory _burnLimits, address[] memory _bridges) {
    _bridges = new address[](1);
    _mintLimits = new uint256[](1);
    _burnLimits = new uint256[](1);
    _bridges[0] = _b;
    _mintLimits[0] = _mint;
    _burnLimits[0] = _burn;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// deployXERC20 — ownership goes straight to _owner, never the deployer
// ─────────────────────────────────────────────────────────────────────────────

contract UnitDeployXERC20 is Base {
  function testTransfersOwnershipToOwnerNotDeployer() public {
    (uint256[] memory _ml, address[] memory _br) = _empty();

    vm.prank(_deployer);
    address _token = _factory.deployXERC20('Superseed', 'SUPR', _ml, _ml, _br, _governor);

    assertEq(SUPRTokenV2(_token).owner(), _governor);
    assertTrue(SUPRTokenV2(_token).owner() != _deployer);
    assertEq(SUPRTokenV2(_token).FACTORY(), address(_factory));
  }

  function testConfiguresBridgeLimits(
    uint256 _mint,
    uint256 _burn
  ) public {
    _mint = bound(_mint, 0, type(uint256).max / 2);
    _burn = bound(_burn, 0, type(uint256).max / 2);
    (uint256[] memory _ml, uint256[] memory _bl, address[] memory _br) = _single(_bridge, _mint, _burn);

    vm.prank(_deployer);
    address _token = _factory.deployXERC20('Superseed', 'SUPR', _ml, _bl, _br, _governor);

    assertEq(SUPRTokenV2(_token).mintingMaxLimitOf(_bridge), _mint);
    assertEq(SUPRTokenV2(_token).burningMaxLimitOf(_bridge), _burn);
  }

  function testRevertsOnLengthMismatch() public {
    uint256[] memory _ml = new uint256[](1);
    uint256[] memory _bl = new uint256[](0);
    address[] memory _br = new address[](1);
    _br[0] = _bridge;

    vm.expectRevert(IXERC20Factory.IXERC20Factory_InvalidLength.selector);
    _factory.deployXERC20('Superseed', 'SUPR', _ml, _bl, _br, _governor);
  }

  function testRedeployingSameSaltReverts() public {
    (uint256[] memory _ml, address[] memory _br) = _empty();

    vm.startPrank(_deployer);
    _factory.deployXERC20('Superseed', 'SUPR', _ml, _ml, _br, _governor);
    // Same (name, symbol, deployer) ⇒ same CREATE3 salt ⇒ collision.
    vm.expectRevert();
    _factory.deployXERC20('Superseed', 'SUPR', _ml, _ml, _br, _governor);
    vm.stopPrank();
  }

  function testRevertsOnZeroOwner() public {
    (uint256[] memory _ml, address[] memory _br) = _empty();
    vm.expectRevert(bytes('Ownable: new owner is the zero address'));
    _factory.deployXERC20('Superseed', 'SUPR', _ml, _ml, _br, address(0));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// deployXERC20WithLockbox — atomic token + lockbox + handoff
// ─────────────────────────────────────────────────────────────────────────────

contract UnitDeployWithLockbox is Base {
  function testDeploysTokenAndLockboxAndTransfersOwnership() public {
    (uint256[] memory _ml, address[] memory _br) = _empty();

    vm.prank(_deployer);
    (address _token, address payable _lockbox) =
      _factory.deployXERC20WithLockbox('Superseed', 'SUPR', _ml, _ml, _br, address(_base), false, _governor);

    assertEq(SUPRTokenV2(_token).owner(), _governor);
    assertEq(SUPRTokenV2(_token).lockbox(), _lockbox);
    assertEq(address(XERC20Lockbox(_lockbox).XERC20()), _token);
    assertEq(address(XERC20Lockbox(_lockbox).ERC20()), address(_base));
    assertFalse(XERC20Lockbox(_lockbox).IS_NATIVE());
  }

  function testRevertsOnBadTokenAddress() public {
    (uint256[] memory _ml, address[] memory _br) = _empty();
    // _baseToken == 0 while not native ⇒ invalid.
    vm.expectRevert(IXERC20Factory.IXERC20Factory_BadTokenAddress.selector);
    _factory.deployXERC20WithLockbox('Superseed', 'SUPR', _ml, _ml, _br, address(0), false, _governor);
  }

  function testNativeLockbox() public {
    (uint256[] memory _ml, address[] memory _br) = _empty();

    vm.prank(_deployer);
    (address _token, address payable _lockbox) =
      _factory.deployXERC20WithLockbox('Superseed', 'SUPR', _ml, _ml, _br, address(0), true, _governor);

    assertEq(SUPRTokenV2(_token).lockbox(), _lockbox);
    assertTrue(XERC20Lockbox(_lockbox).IS_NATIVE());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// deployLockbox — post-hoc, owner-gated, single lockbox
// ─────────────────────────────────────────────────────────────────────────────

contract UnitDeployLockboxStandalone is Base {
  address internal _token;

  function setUp() public override {
    super.setUp();
    (uint256[] memory _ml, address[] memory _br) = _empty();
    vm.prank(_deployer);
    _token = _factory.deployXERC20('Superseed', 'SUPR', _ml, _ml, _br, _governor);
  }

  function testOnlyOwnerCanDeployLockbox() public {
    vm.prank(_deployer); // deployer is NOT the owner (governor is)
    vm.expectRevert(IXERC20Factory.IXERC20Factory_NotOwner.selector);
    _factory.deployLockbox(_token, address(_base), false);
  }

  function testOwnerCanDeployLockbox() public {
    vm.prank(_governor);
    address payable _lockbox = _factory.deployLockbox(_token, address(_base), false);
    assertEq(SUPRTokenV2(_token).lockbox(), _lockbox);
  }

  function testSingleLockboxEnforced() public {
    vm.startPrank(_governor);
    _factory.deployLockbox(_token, address(_base), false);
    vm.expectRevert(IXERC20Factory.IXERC20Factory_LockboxAlreadyDeployed.selector);
    _factory.deployLockbox(_token, address(_base), false);
    vm.stopPrank();
  }
}

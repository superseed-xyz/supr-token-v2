// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {SUPRConverter} from '../../contracts/SUPRConverter.sol';
import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {XERC20} from '@xERC20/contracts/XERC20.sol';
import {Test} from 'forge-std/Test.sol';

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

/// @dev Drives random conversions and tracks the total convertd as a ghost variable.
contract ConverterHandler is Test {
  MockOldSUPR internal _old;
  SUPRTokenV2 internal _new;
  SUPRConverter internal _conv;
  address[] internal _actors;

  uint256 public ghostConverted;

  constructor(
    MockOldSUPR old_,
    SUPRTokenV2 new_,
    SUPRConverter conv_,
    address[] memory actors_
  ) {
    _old = old_;
    _new = new_;
    _conv = conv_;
    _actors = actors_;
  }

  function convert(
    uint256 _actorSeed,
    uint256 _amount
  ) public {
    address _u = _actors[_actorSeed % _actors.length];
    _amount = bound(_amount, 0, _old.balanceOf(_u));
    vm.prank(_u);
    _old.approve(address(_conv), _amount);
    vm.prank(_u);
    try _conv.convert(_amount) {
      ghostConverted += _amount;
    } catch {}
  }

  function convertTo(
    uint256 _actorSeed,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _u = _actors[_actorSeed % _actors.length];
    address _to = _actors[_toSeed % _actors.length];
    _amount = bound(_amount, 0, _old.balanceOf(_u));
    vm.prank(_u);
    _old.approve(address(_conv), _amount);
    vm.prank(_u);
    try _conv.convertTo(_to, _amount) {
      ghostConverted += _amount;
    } catch {}
  }
}

contract SUPRConverterInvariants is Test {
  MockOldSUPR internal _old;
  SUPRTokenV2 internal _new;
  SUPRConverter internal _conv;
  ConverterHandler internal _handler;

  address internal _governor = vm.addr(0x600E);
  uint256 internal constant _INITIAL_OLD_SUPPLY = 3000e18;

  function setUp() public {
    _old = new MockOldSUPR(_governor);
    _new = new SUPRTokenV2('Superseed', 'SUPR', _governor);
    _conv = new SUPRConverter(address(_old), address(_new));

    address[] memory _actors = new address[](3);
    _actors[0] = vm.addr(0xA1);
    _actors[1] = vm.addr(0xA2);
    _actors[2] = vm.addr(0xA3);

    // Fund actors with V1 SUPR (total == _INITIAL_OLD_SUPPLY).
    _old.freeMint(_actors[0], 1000e18);
    _old.freeMint(_actors[1], 1000e18);
    _old.freeMint(_actors[2], 1000e18);

    // Register converter: burner on old, minter on new, both above total supply so the
    // limits never bind (we want to test conservation, not rate limiting).
    vm.startPrank(_governor);
    _old.setLimits(address(_conv), 0, type(uint256).max / 2);
    _new.setLimits(address(_conv), type(uint256).max / 2, 0);
    vm.stopPrank();

    _handler = new ConverterHandler(_old, _new, _conv, _actors);

    // Restrict fuzzing to the handler's own actions (not forge-std inherited functions).
    bytes4[] memory _selectors = new bytes4[](2);
    _selectors[0] = ConverterHandler.convert.selector;
    _selectors[1] = ConverterHandler.convertTo.selector;
    targetSelector(FuzzSelector({addr: address(_handler), selectors: _selectors}));
    targetContract(address(_handler));
  }

  /// @notice Conservation: V1 burned + V1 remaining == initial V1 supply, and every V2 minted
  ///         is backed 1:1 by a burned V1. Conversion can never inflate total token supply.
  function invariant_oneToOneConservation() public {
    assertEq(_new.totalSupply(), _handler.ghostConverted(), 'V2 minted != V1 convertd');
    assertEq(_old.totalSupply(), _INITIAL_OLD_SUPPLY - _handler.ghostConverted(), 'V1 burned mismatch');
    assertEq(_old.totalSupply() + _new.totalSupply(), _INITIAL_OLD_SUPPLY, 'total supply not conserved');
  }

  /// @notice The converter can never mint more V2 than the V1 that ever existed.
  function invariant_v2NeverExceedsInitialV1() public {
    assertLe(_new.totalSupply(), _INITIAL_OLD_SUPPLY);
  }
}

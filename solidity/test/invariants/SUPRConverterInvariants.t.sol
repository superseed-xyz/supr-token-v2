// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {LobsterToken} from '../../contracts/LobsterToken.sol';
import {SUPRConverter} from '../../contracts/SUPRConverter.sol';
import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {XERC20} from '@xERC20/contracts/XERC20.sol';
import {Test} from 'forge-std/Test.sol';

/// @dev xERC20-based stand-in for V1 SUPR / SUPR0 (CrosschainERC20 on mainnet).
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

/// @dev Drives random split conversions and tracks expected outputs as ghost variables.
contract ConverterHandler is Test {
  MockOldSUPR internal _old;
  SUPRTokenV2 internal _new;
  LobsterToken internal _build;
  SUPRConverter internal _conv;
  address[] internal _actors;

  uint256 public ghostBurned;
  uint256 public ghostSuprMinted;
  uint256 public ghostBuildMinted;
  uint256 public ghostSupr0Routed;

  constructor(
    MockOldSUPR old_,
    SUPRTokenV2 new_,
    LobsterToken build_,
    SUPRConverter conv_,
    address[] memory actors_
  ) {
    _old = old_;
    _new = new_;
    _build = build_;
    _conv = conv_;
    _actors = actors_;
  }

  function _record(
    uint256 _amount,
    uint256 _suprBps
  ) internal {
    (uint256 _suprOut, uint256 _buildOut) = _conv.previewConvert(_amount, _suprBps);
    ghostBurned += _amount;
    ghostSuprMinted += _suprOut;
    ghostBuildMinted += _buildOut;
    ghostSupr0Routed += _amount; // supr0ForSupr + supr0ForBuild == amount, by construction
  }

  function convert(
    uint256 _actorSeed,
    uint256 _amount,
    uint256 _suprBps
  ) public {
    address _u = _actors[_actorSeed % _actors.length];
    _amount = bound(_amount, 0, _old.balanceOf(_u));
    _suprBps = bound(_suprBps, 0, _conv.BPS_DENOMINATOR());
    vm.prank(_u);
    _old.approve(address(_conv), _amount);
    vm.prank(_u);
    try _conv.convert(_amount, _suprBps) {
      _record(_amount, _suprBps);
    } catch {}
  }

  function convertTo(
    uint256 _actorSeed,
    uint256 _toSeed,
    uint256 _amount,
    uint256 _suprBps
  ) public {
    address _u = _actors[_actorSeed % _actors.length];
    address _to = _actors[_toSeed % _actors.length];
    _amount = bound(_amount, 0, _old.balanceOf(_u));
    _suprBps = bound(_suprBps, 0, _conv.BPS_DENOMINATOR());
    vm.prank(_u);
    _old.approve(address(_conv), _amount);
    vm.prank(_u);
    try _conv.convertTo(_to, _amount, _suprBps) {
      _record(_amount, _suprBps);
    } catch {}
  }
}

contract SUPRConverterInvariants is Test {
  MockOldSUPR internal _old;
  SUPRTokenV2 internal _new;
  LobsterToken internal _build;
  SUPRConverter internal _conv;
  ConverterHandler internal _handler;

  address internal _governor = vm.addr(0x600E);
  uint256 internal constant _INITIAL_OLD_SUPPLY = 3000e18;

  function setUp() public {
    _old = new MockOldSUPR(_governor);
    vm.startPrank(_governor);
    _new = new SUPRTokenV2('Superseed', 'SUPR', _governor);
    _build = new LobsterToken('Lobsters', 'BUILD', _governor);
    vm.stopPrank();
    _conv = new SUPRConverter(address(_old), address(_new), address(_build));

    address[] memory _actors = new address[](3);
    _actors[0] = vm.addr(0xA1);
    _actors[1] = vm.addr(0xA2);
    _actors[2] = vm.addr(0xA3);

    // Fund actors with SUPR0 (total == _INITIAL_OLD_SUPPLY).
    _old.freeMint(_actors[0], 1000e18);
    _old.freeMint(_actors[1], 1000e18);
    _old.freeMint(_actors[2], 1000e18);

    // Register converter: burner on old, minter on both new tokens, all above any reachable
    // amount so the limits never bind (we test conservation, not rate limiting).
    vm.startPrank(_governor);
    _old.setLimits(address(_conv), 0, type(uint256).max / 2);
    _new.setLimits(address(_conv), type(uint256).max / 2, 0);
    _build.setLimits(address(_conv), type(uint256).max / 2, 0);
    vm.stopPrank();

    _handler = new ConverterHandler(_old, _new, _build, _conv, _actors);

    // Restrict fuzzing to the handler's own actions (not forge-std inherited functions).
    bytes4[] memory _selectors = new bytes4[](2);
    _selectors[0] = ConverterHandler.convert.selector;
    _selectors[1] = ConverterHandler.convertTo.selector;
    targetSelector(FuzzSelector({addr: address(_handler), selectors: _selectors}));
    targetContract(address(_handler));
  }

  /// @notice Every SUPR1 and BUILD minted is backed by burned SUPR0 at the fixed rates, and
  ///         all burned SUPR0 is fully accounted for across the two output legs.
  function invariant_outputsBackedByBurnedOld() public {
    assertEq(_new.totalSupply(), _handler.ghostSuprMinted(), 'SUPR1 minted mismatch');
    assertEq(_build.totalSupply(), _handler.ghostBuildMinted(), 'BUILD minted mismatch');
    assertEq(_old.totalSupply(), _INITIAL_OLD_SUPPLY - _handler.ghostBurned(), 'SUPR0 burned mismatch');
    assertEq(_handler.ghostSupr0Routed(), _handler.ghostBurned(), 'routed SUPR0 != burned SUPR0');
  }

  /// @notice Strong conservation: every burned SUPR0 wei is backed by minted output at the fixed
  ///         rates — none is destroyed to truncation dust. SUPR1 consumes SUPR0_PER_SUPR1 each;
  ///         BUILD consumes one SUPR0 per BUILD_PER_SUPR0 minted (BUILD always divides evenly).
  function invariant_noBurnedSupr0Lost() public {
    uint256 _backed =
      _handler.ghostSuprMinted() * _conv.SUPR0_PER_SUPR1() + _handler.ghostBuildMinted() / _conv.BUILD_PER_SUPR0();
    assertEq(_backed, _handler.ghostBurned(), 'burned SUPR0 not fully backed by minted output');
  }

  /// @notice The converter can never mint more than the maximum implied by the SUPR0 that ever
  ///         existed: SUPR1 ≤ initial/SUPR0_PER_SUPR1, BUILD ≤ initial*BUILD_PER_SUPR0.
  function invariant_outputsNeverExceedMax() public {
    assertLe(_new.totalSupply(), _INITIAL_OLD_SUPPLY / _conv.SUPR0_PER_SUPR1());
    assertLe(_build.totalSupply(), _INITIAL_OLD_SUPPLY * _conv.BUILD_PER_SUPR0());
  }

  /// @notice SUPR0 supply only ever decreases — conversion can never inflate the old token.
  function invariant_oldSupplyNeverInflates() public {
    assertLe(_old.totalSupply(), _INITIAL_OLD_SUPPLY);
  }
}

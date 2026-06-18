// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {SUPRTokenV2} from '../../contracts/SUPRTokenV2.sol';
import {Test} from 'forge-std/Test.sol';

/// @dev Upper bound for fuzzed mint amounts (the V1 SUPR total supply); not a contract-enforced cap.
uint256 constant FUZZ_MAX = 10_000_000_000e18;

/// @dev Drives random mint/burn/transfer/setLimits against a SUPRTokenV2 from a fixed set
///      of bridges and user actors. All calls are wrapped in try/catch so the fuzzer keeps
///      exploring after expected reverts (limit/allowance/receiver-guard).
contract TokenHandler is Test {
  SUPRTokenV2 internal _token;
  address internal _owner;
  address[] internal _bridges;
  address[] internal _actors;

  constructor(
    SUPRTokenV2 token_,
    address owner_,
    address[] memory bridges_,
    address[] memory actors_
  ) {
    _token = token_;
    _owner = owner_;
    _bridges = bridges_;
    _actors = actors_;
  }

  function mint(
    uint256 _bridgeSeed,
    uint256 _actorSeed,
    uint256 _amount
  ) public {
    address _bridge = _bridges[_bridgeSeed % _bridges.length];
    address _to = _actors[_actorSeed % _actors.length];
    _amount = bound(_amount, 0, FUZZ_MAX);
    vm.prank(_bridge);
    try _token.mint(_to, _amount) {} catch {}
  }

  function burn(
    uint256 _bridgeSeed,
    uint256 _actorSeed,
    uint256 _amount
  ) public {
    address _bridge = _bridges[_bridgeSeed % _bridges.length];
    address _from = _actors[_actorSeed % _actors.length];
    _amount = bound(_amount, 0, _token.balanceOf(_from));
    vm.prank(_from);
    _token.approve(_bridge, _amount);
    vm.prank(_bridge);
    try _token.burn(_from, _amount) {} catch {}
  }

  function transfer(
    uint256 _fromSeed,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _from = _actors[_fromSeed % _actors.length];
    address _to = _actors[_toSeed % _actors.length];
    _amount = bound(_amount, 0, _token.balanceOf(_from));
    vm.prank(_from);
    try _token.transfer(_to, _amount) {} catch {}
  }

  /// @dev Deliberately attempts the receiver-guard-forbidden targets; must always revert.
  function transferToForbidden(
    uint256 _actorSeed,
    uint256 _amount,
    bool _toZero
  ) public {
    address _from = _actors[_actorSeed % _actors.length];
    address _to = _toZero ? address(0) : address(_token);
    _amount = bound(_amount, 0, _token.balanceOf(_from));
    vm.prank(_from);
    try _token.transfer(_to, _amount) {} catch {}
  }

  function setLimits(
    uint256 _bridgeSeed,
    uint256 _mintLimit,
    uint256 _burnLimit
  ) public {
    address _bridge = _bridges[_bridgeSeed % _bridges.length];
    _mintLimit = bound(_mintLimit, 0, type(uint256).max / 2);
    _burnLimit = bound(_burnLimit, 0, type(uint256).max / 2);
    vm.prank(_owner);
    _token.setLimits(_bridge, _mintLimit, _burnLimit);
  }

  function bridges() external view returns (address[] memory) {
    return _bridges;
  }
}

contract SUPRTokenV2Invariants is Test {
  SUPRTokenV2 internal _token;
  TokenHandler internal _handler;
  address internal _owner = vm.addr(0xA11CE);

  function setUp() public {
    _token = new SUPRTokenV2(_owner);

    address[] memory _bridges = new address[](2);
    _bridges[0] = vm.addr(0xB1);
    _bridges[1] = vm.addr(0xB2);

    address[] memory _actors = new address[](3);
    _actors[0] = vm.addr(0xACC1);
    _actors[1] = vm.addr(0xACC2);
    _actors[2] = vm.addr(0xACC3);

    // Seed generous starting limits so the fuzzer can actually move tokens.
    vm.startPrank(_owner);
    _token.setLimits(_bridges[0], 5_000_000_000e18, 5_000_000_000e18);
    _token.setLimits(_bridges[1], 5_000_000_000e18, 5_000_000_000e18);
    vm.stopPrank();

    _handler = new TokenHandler(_token, _owner, _bridges, _actors);

    // Restrict fuzzing to the handler's own actions (not forge-std inherited functions).
    bytes4[] memory _selectors = new bytes4[](5);
    _selectors[0] = TokenHandler.mint.selector;
    _selectors[1] = TokenHandler.burn.selector;
    _selectors[2] = TokenHandler.transfer.selector;
    _selectors[3] = TokenHandler.transferToForbidden.selector;
    _selectors[4] = TokenHandler.setLimits.selector;
    targetSelector(FuzzSelector({addr: address(_handler), selectors: _selectors}));
    targetContract(address(_handler));
  }

  /// @notice The available (current) limit can never exceed the configured max limit.
  function invariant_currentLimitNeverExceedsMax() public {
    address[] memory _bridges = _handler.bridges();
    for (uint256 _i; _i < _bridges.length; _i++) {
      assertLe(_token.mintingCurrentLimitOf(_bridges[_i]), _token.mintingMaxLimitOf(_bridges[_i]));
      assertLe(_token.burningCurrentLimitOf(_bridges[_i]), _token.burningMaxLimitOf(_bridges[_i]));
    }
  }

  /// @notice The receiver guard holds: tokens never get trapped at address(0) or the token itself.
  function invariant_noTrappedTokens() public {
    assertEq(_token.balanceOf(address(0)), 0);
    assertEq(_token.balanceOf(address(_token)), 0);
  }
}

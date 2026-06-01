// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {SUPRTokenV2} from '../contracts/SUPRTokenV2.sol';
import {IXERC20Factory} from '../interfaces/IXERC20Factory.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {XERC20Lockbox} from '@xERC20/contracts/XERC20Lockbox.sol';
import {CREATE3} from 'solady/utils/CREATE3.sol';

/**
 * @title SUPRTokenV2Factory
 * @notice Deploys SUPRTokenV2 tokens and XERC20Lockbox instances at deterministic
 *         addresses across every chain via CREATE3.
 *
 *         The salt for a token is derived from (name, symbol, deployer), guaranteeing
 *         the same address on all chains when called from the same EOA/multisig.
 *
 *         Lockboxes should only be deployed on chains that have a canonical ERC20 to
 *         wrap (Superseed chain: V1 SUPR).  Ethereum mainnet runs crosschainERC20.
 */
contract SUPRTokenV2Factory is IXERC20Factory {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @dev xerc20 address → lockbox address (zero if none deployed yet)
  mapping(address => address) internal _lockboxRegistry;

  EnumerableSet.AddressSet internal _lockboxRegistryArray;
  EnumerableSet.AddressSet internal _xerc20RegistryArray;

  // -------------------------------------------------------------------------
  // External
  // -------------------------------------------------------------------------

  /**
   * @notice Deploys a SUPRTokenV2 token using CREATE3, configures bridge limits, and
   *         transfers ownership to `_owner` — all in one call.
   * @dev    The CREATE3 salt is keyed on the *deployer* (msg.sender), not `_owner`, so the
   *         same deployer EOA yields the same token address on every chain even when the
   *         owner (e.g. a per-chain governor multisig) differs. Ownership never passes
   *         through the deployer EOA.
   * @param _name         Token name
   * @param _symbol       Token symbol
   * @param _minterLimits 24-hour minting limits per bridge (parallel array with _bridges)
   * @param _burnerLimits 24-hour burning limits per bridge (parallel array with _bridges)
   * @param _bridges      Bridge addresses to configure at deploy time
   * @param _owner        Address that will own the token (e.g. governor multisig)
   * @return _xerc20      Address of the deployed token
   */
  function deployXERC20(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    address _owner
  ) external returns (address _xerc20) {
    _xerc20 = _deployXERC20(_name, _symbol, _minterLimits, _burnerLimits, _bridges);
    SUPRTokenV2(_xerc20).transferOwnership(_owner);
    emit XERC20Deployed(_xerc20);
  }

  /**
   * @notice Atomically deploys a SUPRTokenV2 token AND its XERC20Lockbox, configures bridge
   *         limits, then transfers ownership to `_owner` — all in one call.
   * @dev    Use on chains with a canonical ERC20 to wrap (e.g. Ethereum mainnet: V1 SUPR).
   *         The lockbox is set while the factory still owns the token, so the deployer EOA
   *         is never the owner. Salt determinism is identical to deployXERC20.
   * @param _name         Token name
   * @param _symbol       Token symbol
   * @param _minterLimits 24-hour minting limits per bridge (parallel array with _bridges)
   * @param _burnerLimits 24-hour burning limits per bridge (parallel array with _bridges)
   * @param _bridges      Bridge addresses to configure at deploy time
   * @param _baseToken    Canonical ERC20 to wrap (address(0) if native gas token)
   * @param _isNative     True if wrapping the chain's native gas token
   * @param _owner        Address that will own the token (e.g. governor multisig)
   * @return _xerc20      Address of the deployed token
   * @return _lockbox     Address of the deployed lockbox
   */
  function deployXERC20WithLockbox(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    address _baseToken,
    bool _isNative,
    address _owner
  ) external returns (address _xerc20, address payable _lockbox) {
    if ((_baseToken == address(0) && !_isNative) || (_isNative && _baseToken != address(0))) {
      revert IXERC20Factory_BadTokenAddress();
    }

    _xerc20 = _deployXERC20(_name, _symbol, _minterLimits, _burnerLimits, _bridges);
    _lockbox = _deployLockbox(_xerc20, _baseToken, _isNative);
    SUPRTokenV2(_xerc20).transferOwnership(_owner);

    emit XERC20Deployed(_xerc20);
    emit LockboxDeployed(_lockbox);
  }

  /**
   * @notice Deploys a XERC20Lockbox for a SUPRTokenV2 that was deployed earlier (post-hoc).
   * @dev    For first-time deployment prefer deployXERC20WithLockbox, which avoids a
   *         transient ownership window. This path is for adding a lockbox after the token
   *         is already owned by the governor: only the current owner may call it, and a
   *         single lockbox per xERC20 is enforced. setLockbox works because the factory is
   *         the token's immutable FACTORY, regardless of who owns it.
   * @param _xerc20    Address of the SUPRTokenV2 token
   * @param _baseToken Address of the canonical ERC20 to wrap (address(0) if native gas token)
   * @param _isNative  True if wrapping the chain's native gas token
   * @return _lockbox  Address of the deployed lockbox
   */
  function deployLockbox(
    address _xerc20,
    address _baseToken,
    bool _isNative
  ) external returns (address payable _lockbox) {
    if ((_baseToken == address(0) && !_isNative) || (_isNative && _baseToken != address(0))) {
      revert IXERC20Factory_BadTokenAddress();
    }
    if (SUPRTokenV2(_xerc20).owner() != msg.sender) revert IXERC20Factory_NotOwner();
    if (_lockboxRegistry[_xerc20] != address(0)) revert IXERC20Factory_LockboxAlreadyDeployed();

    _lockbox = _deployLockbox(_xerc20, _baseToken, _isNative);
    emit LockboxDeployed(_lockbox);
  }

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  /// @dev Deploys + configures the token but leaves ownership with the factory.
  ///      Callers are responsible for the final transferOwnership to the intended owner.
  function _deployXERC20(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges
  ) internal returns (address _xerc20) {
    uint256 _bridgesLength = _bridges.length;
    if (_minterLimits.length != _bridgesLength || _burnerLimits.length != _bridgesLength) {
      revert IXERC20Factory_InvalidLength();
    }

    // abi.encode (not encodePacked): packed encoding of consecutive dynamic types is
    // ambiguous, e.g. ("AB","C") and ("A","BC") collide. encode is collision-safe.
    bytes32 _salt = keccak256(abi.encode(_name, _symbol, msg.sender));
    bytes memory _creation = type(SUPRTokenV2).creationCode;
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_name, _symbol, address(this)));

    _xerc20 = CREATE3.deployDeterministic(_bytecode, _salt);
    EnumerableSet.add(_xerc20RegistryArray, _xerc20);

    for (uint256 _i; _i < _bridgesLength; ++_i) {
      SUPRTokenV2(_xerc20).setLimits(_bridges[_i], _minterLimits[_i], _burnerLimits[_i]);
    }
  }

  function _deployLockbox(
    address _xerc20,
    address _baseToken,
    bool _isNative
  ) internal returns (address payable _lockbox) {
    bytes32 _salt = keccak256(abi.encodePacked(_xerc20, _baseToken, msg.sender));
    bytes memory _creation = type(XERC20Lockbox).creationCode;
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_xerc20, _baseToken, _isNative));

    _lockbox = payable(CREATE3.deployDeterministic(_bytecode, _salt));

    SUPRTokenV2(_xerc20).setLockbox(address(_lockbox));
    EnumerableSet.add(_lockboxRegistryArray, _lockbox);
    _lockboxRegistry[_xerc20] = _lockbox;
  }
}

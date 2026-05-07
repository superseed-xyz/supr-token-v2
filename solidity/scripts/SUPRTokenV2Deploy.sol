// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// solhint-disable-next-line no-console
import {console} from 'forge-std/console.sol';
import {Script} from 'forge-std/Script.sol';
import {stdJson} from 'forge-std/StdJson.sol';
import {SUPRTokenV2} from '../contracts/SUPRTokenV2.sol';
import {SUPRTokenV2Factory} from '../contracts/SUPRTokenV2Factory.sol';
import {ScriptingLibrary} from './ScriptingLibrary/ScriptingLibrary.sol';

/// @dev Struct members must be in ALPHABETICAL order — stdJson parses JSON keys
///      alphabetically and maps them positionally to struct fields.
struct BridgeDetails {
  address bridge; // Bridge contract address on this chain
  uint256 burnLimit; // 24-hour burn quota in whole tokens (scaled by 1e18 in script)
  uint256 mintLimit; // 24-hour mint quota in whole tokens (scaled by 1e18 in script)
}

/// @dev Struct members must be in ALPHABETICAL order — stdJson parses JSON keys
///      alphabetically and maps them positionally to struct fields.
struct ChainDetails {
  BridgeDetails[] bridgeDetails; // Bridges authorised on this chain
  bool deploy; // Set to true to include this chain in the current deployment run
  address erc20; // Canonical ERC20 to wrap in a lockbox (address(0) = no lockbox)
  address governor; // Multisig / DAO that will own the token after deployment
  bool isNativeGasToken; // True only if wrapping the chain's native gas token
  string rpcEnvName; // Name of the RPC env var in .env (e.g. "MAINNET_RPC")
}

/// @dev Struct members must be in ALPHABETICAL order — stdJson parses JSON keys
///      alphabetically and maps them positionally to struct fields.
struct DeploymentConfig {
  ChainDetails[] chainDetails;
  string name; // Token name
  string symbol; // Token symbol
}

/**
 * @title SUPRTokenV2Deploy
 * @notice Deploys SUPRTokenV2 (and optionally a lockbox) on every chain listed in the
 *         deployment config.  After the loop it asserts that the token landed at the same
 *         address on every chain — the CREATE3 determinism guarantee.
 *
 * Usage:
 *   1. Fill in solidity/scripts/supr-token-v2-deployment-config.json
 *   2. Set DEPLOYER_PRIVATE_KEY, FACTORY_ADDRESS, and all RPC env vars in .env
 *   3. Dry-run:  forge script solidity/scripts/SUPRTokenV2Deploy.sol --via-ir
 *   4. Broadcast: add --broadcast --verify to the command above
 *
 * The factory must already be deployed on every target chain.
 * Run SUPRTokenV2FactoryDeploy.sol first if it is not.
 */
contract SUPRTokenV2Deploy is Script, ScriptingLibrary {
  using stdJson for string;

  error SUPRTokenV2Deploy_FactoryAddressNotSet();
  error SUPRTokenV2Deploy_GovernorNotSet();
  error SUPRTokenV2Deploy_NoFactoryOnChain();
  error SUPRTokenV2Deploy_BridgeAddressNotSet();
  error SUPRTokenV2Deploy_AddressMismatchAcrossChains();
  error SUPRTokenV2Deploy_BytecodeMismatchAcrossChains();

  uint256 public deployer = vm.envUint('DEPLOYER_PRIVATE_KEY');
  SUPRTokenV2Factory public factory = SUPRTokenV2Factory(vm.envAddress('FACTORY_ADDRESS'));

  function run() public {
    if (address(factory) == address(0)) revert SUPRTokenV2Deploy_FactoryAddressNotSet();

    string memory _json = vm.readFile('./solidity/scripts/supr-token-v2-deployment-config.json');
    DeploymentConfig memory _data = abi.decode(_json.parseRaw('.'), (DeploymentConfig));
    uint256 _chainAmount = _data.chainDetails.length;

    // Pre-count enabled chains so we allocate exact-sized arrays for the determinism check.
    uint256 _deployCount;
    for (uint256 i; i < _chainAmount; i++) {
      if (_data.chainDetails[i].deploy) _deployCount++;
    }

    address[] memory _tokens = new address[](_deployCount);
    uint256[] memory _forkIds = new uint256[](_deployCount);
    uint256 _idx;

    for (uint256 i; i < _chainAmount; i++) {
      ChainDetails memory _chainDetails = _data.chainDetails[i];

      if (!_chainDetails.deploy) continue;

      if (_chainDetails.governor == address(0)) revert SUPRTokenV2Deploy_GovernorNotSet();

      _forkIds[_idx] = vm.createSelectFork(vm.rpcUrl(vm.envString(_chainDetails.rpcEnvName)));
      vm.startBroadcast(deployer);

      if (keccak256(address(factory).code) == keccak256(address(0).code)) {
        revert SUPRTokenV2Deploy_NoFactoryOnChain();
      }

      // Flatten bridge details arrays.
      BridgeDetails[] memory _bridgeDetails = _chainDetails.bridgeDetails;
      address[] memory _bridges = new address[](_bridgeDetails.length);
      uint256[] memory _burnLimits = new uint256[](_bridgeDetails.length);
      uint256[] memory _mintLimits = new uint256[](_bridgeDetails.length);
      for (uint256 _b; _b < _bridgeDetails.length; _b++) {
        if (_bridgeDetails[_b].bridge == address(0)) revert SUPRTokenV2Deploy_BridgeAddressNotSet();
        _bridges[_b] = _bridgeDetails[_b].bridge;
        _burnLimits[_b] = _bridgeDetails[_b].burnLimit * 1e18;
        _mintLimits[_b] = _bridgeDetails[_b].mintLimit * 1e18;
      }

      // Deploy the xERC20 token.
      address _xerc20 = factory.deployXERC20(_data.name, _data.symbol, _mintLimits, _burnLimits, _bridges);

      // Deploy a lockbox only when a canonical ERC20 exists on this chain.
      address _lockbox;
      if (_chainDetails.erc20 != address(0) || _chainDetails.isNativeGasToken) {
        _lockbox = factory.deployLockbox(_xerc20, _chainDetails.erc20, _chainDetails.isNativeGasToken);
      }

      // Hand ownership to the governor (multisig / DAO).
      SUPRTokenV2(_xerc20).transferOwnership(_chainDetails.governor);

      vm.stopBroadcast();

      // solhint-disable-next-line no-console
      console.log('[%s] xERC20: %s', _chainDetails.rpcEnvName, _xerc20);
      if (_lockbox != address(0)) {
        // solhint-disable-next-line no-console
        console.log('[%s] Lockbox: %s', _chainDetails.rpcEnvName, _lockbox);
      }
      _tokens[_idx] = _xerc20;
      _idx++;
    }

    // Verify deterministic deployment: same address and bytecode on every deployed chain.
    // Each bytecode read switches to that chain's fork so .code hits the correct RPC.
    if (_deployCount > 1) {
      vm.selectFork(_forkIds[0]);
      bytes32 _referenceCodehash = keccak256(_tokens[0].code);

      for (uint256 i = 1; i < _deployCount; i++) {
        if (_tokens[i - 1] != _tokens[i]) revert SUPRTokenV2Deploy_AddressMismatchAcrossChains();

        vm.selectFork(_forkIds[i]);
        if (keccak256(_tokens[i].code) != _referenceCodehash) {
          revert SUPRTokenV2Deploy_BytecodeMismatchAcrossChains();
        }
      }
    }
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// solhint-disable-next-line no-console
import {LobsterTokenFactory} from '../contracts/LobsterTokenFactory.sol';
import {ScriptingLibrary} from './ScriptingLibrary/ScriptingLibrary.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title LobsterTokenFactoryDeploy
 * @notice Deploys the LobsterTokenFactory with a deterministic CREATE2 salt so it lands
 *         at the same address on every chain.
 *
 * IMPORTANT: Update SALT whenever a new factory version needs to be deployed to avoid
 * address collisions with existing deployments.
 *
 * Usage:
 *   Dry-run:  forge script solidity/scripts/LobsterTokenFactoryDeploy.sol --via-ir
 *   Broadcast: add --broadcast --verify
 */
contract LobsterTokenFactoryDeploy is Script, ScriptingLibrary {
  // Bump this string for every new factory version to get a fresh address.
  string public constant SALT = 'LobsterTokenFactory-v1.0';

  function run() public {
    // Broadcaster is provided via `--account <keystore>` (no raw private key in env).
    bytes32 _salt = keccak256(abi.encodePacked(SALT, msg.sender));

    vm.startBroadcast();
    LobsterTokenFactory _factory = new LobsterTokenFactory{salt: _salt}();
    vm.stopBroadcast();

    // solhint-disable-next-line no-console
    console.log('LobsterTokenFactory deployed to:', address(_factory));
    // Copy this address into LobsterTokenDeploy.sol before running the token deployment.
  }
}

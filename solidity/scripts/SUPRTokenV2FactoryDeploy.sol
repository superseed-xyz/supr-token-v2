// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// solhint-disable-next-line no-console
import {console} from 'forge-std/console.sol';
import {Script} from 'forge-std/Script.sol';
import {SUPRTokenV2Factory} from '../contracts/SUPRTokenV2Factory.sol';
import {ScriptingLibrary} from './ScriptingLibrary/ScriptingLibrary.sol';

/**
 * @title SUPRTokenV2FactoryDeploy
 * @notice Deploys the SUPRTokenV2Factory with a deterministic CREATE2 salt so it lands
 *         at the same address on every chain.
 *
 * IMPORTANT: Update SALT whenever a new factory version needs to be deployed to avoid
 * address collisions with existing deployments.
 *
 * Usage:
 *   Dry-run:  forge script solidity/scripts/SUPRTokenV2FactoryDeploy.sol --via-ir
 *   Broadcast: add --broadcast --verify
 */
contract SUPRTokenV2FactoryDeploy is Script, ScriptingLibrary {
  // Bump this string for every new factory version to get a fresh address.
  string public constant SALT = 'SUPRTokenV2Factory-v1.1';

  uint256 public deployerPk = vm.envUint('DEPLOYER_PRIVATE_KEY');

  function run() public {
    bytes32 _salt = keccak256(abi.encodePacked(SALT, msg.sender));

    vm.startBroadcast(deployerPk);
    SUPRTokenV2Factory _factory = new SUPRTokenV2Factory{salt: _salt}();
    vm.stopBroadcast();

    // solhint-disable-next-line no-console
    console.log('SUPRTokenV2Factory deployed to:', address(_factory));
    // Copy this address into SUPRTokenV2Deploy.sol before running the token deployment.
  }
}

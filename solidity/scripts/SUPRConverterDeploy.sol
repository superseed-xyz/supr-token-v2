// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// solhint-disable-next-line no-console
import {console} from 'forge-std/console.sol';
import {Script} from 'forge-std/Script.sol';
import {SUPRConverter} from '../contracts/SUPRConverter.sol';
import {IXERC20} from '../interfaces/IXERC20.sol';

/**
 * @title SUPRConverterDeploy
 * @notice Deploys the SUPRConverter and registers it as a bridge on the new token.
 *
 * Prerequisites:
 *   - SUPRTokenV2 must already be deployed (set NEW_TOKEN below)
 *   - DEPLOYER_PRIVATE_KEY must be the current owner of SUPRTokenV2 (governor)
 *
 * Set env vars in .env:
 *   DEPLOYER_PRIVATE_KEY=...
 *   OLD_TOKEN_ADDRESS=<V1 SUPR token address>
 *   NEW_TOKEN_ADDRESS=<deployed SUPRTokenV2 address>
 *
 * The migration limit is set to the total V1 supply (10 billion tokens).
 * When migration is complete, the governor calls:
 *   newSUPR.setLimits(migrationBridge, 0, 0)
 * to permanently close the migrator.
 */
contract SUPRConverterDeploy is Script {
  uint256 internal constant OLD_TOTAL_SUPPLY = 10_000_000_000e18;

  uint256 public deployerPk = vm.envUint('DEPLOYER_PRIVATE_KEY');
  address public oldSupr = vm.envAddress('OLD_TOKEN_ADDRESS');
  address public newSupr = vm.envAddress('NEW_TOKEN_ADDRESS');

  function run() public {
    vm.startBroadcast(deployerPk);
    SUPRConverter _migrator = new SUPRConverter(oldSupr, newSupr);
    vm.stopBroadcast();

    // setLimits is onlyOwner on both tokens. Log calldatas for the governor to execute.

    // 1. New token: grant converter mint rights (mint limit = total old supply, burn limit = 0).
    bytes memory _setLimitsNew =
      abi.encodeCall(IXERC20.setLimits, (address(_migrator), OLD_TOTAL_SUPPLY, 0));

    // 2. Old token: grant converter burn rights (mint limit = 0, burn limit = total old supply).
    bytes memory _setLimitsOld =
      abi.encodeCall(IXERC20.setLimits, (address(_migrator), 0, OLD_TOTAL_SUPPLY));

    // solhint-disable-next-line no-console
    console.log('SUPRConverter deployed:', address(_migrator));
    // solhint-disable-next-line no-console
    console.log('--- ACTION 1: owner of OLD token (%s) must call setLimits:', oldSupr);
    // solhint-disable-next-line no-console
    console.logBytes(_setLimitsOld);
    // solhint-disable-next-line no-console
    console.log('--- ACTION 2: owner of NEW token (%s) must call setLimits:', newSupr);
    // solhint-disable-next-line no-console
    console.logBytes(_setLimitsNew);
    // solhint-disable-next-line no-console
    console.log('To close migration: owners call setLimits(migrator, 0, 0) on both tokens');
  }
}

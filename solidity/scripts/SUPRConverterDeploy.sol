// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// solhint-disable-next-line no-console
import {SUPRConverter} from '../contracts/SUPRConverter.sol';
import {IXERC20} from '@xERC20/interfaces/IXERC20.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title SUPRConverterDeploy
 * @notice Deploys the SUPRConverter and prints the calldata each token's owner must execute
 *         to register it as a bridge (burner on SUPR0, minter on SUPR1 and BUILD).
 *
 * Prerequisites:
 *   - SUPR0 (old SUPR), SUPR1 (SUPRTokenV2) and BUILD (LobsterToken) must already be deployed
 *   - Ownership of SUPR1 and BUILD has been transferred to the governor (multisig / DAO)
 *
 * Set env vars in .env:
 *   OLD_TOKEN_ADDRESS=<V1 SUPR / SUPR0 token address>
 *   NEW_TOKEN_ADDRESS=<deployed SUPRTokenV2 / SUPR1 address>
 *   BUILD_TOKEN_ADDRESS=<deployed LobsterToken / BUILD address>
 *
 * After this script runs, each token's owner must call setLimits with the printed calldata.
 * When conversion is complete, the owners call setLimits(converter, 0, 0) to close it.
 */
contract SUPRConverterDeploy is Script {
  /// @dev Fixed total supply of V1 SUPR (SUPR0); bounds every per-token rate limit below.
  uint256 internal constant OLD_TOTAL_SUPPLY = 10_000_000_000e18;

  address public oldSupr = vm.envAddress('OLD_TOKEN_ADDRESS');
  address public newSupr = vm.envAddress('NEW_TOKEN_ADDRESS');
  address public build = vm.envAddress('BUILD_TOKEN_ADDRESS');

  function run() public {
    // Broadcaster is provided via `--account <keystore>` (no raw private key in env).
    vm.startBroadcast();
    SUPRConverter _converter = new SUPRConverter(oldSupr, newSupr, build);
    vm.stopBroadcast();

    // Per-token mint ceilings derived from the converter's fixed rates and the old supply.
    // Max SUPR1 ever mintable: every SUPR0 routed to SUPR1 at the 1/SUPR0_PER_SUPR1 rate.
    uint256 _suprMintLimit = OLD_TOTAL_SUPPLY / _converter.SUPR0_PER_SUPR1();
    // Max BUILD ever mintable: every SUPR0 routed to BUILD at the BUILD_PER_SUPR0 rate.
    uint256 _buildMintLimit = OLD_TOTAL_SUPPLY * _converter.BUILD_PER_SUPR0();

    // setLimits is onlyOwner on each token. Log calldatas for the owners to execute.

    // 1. Old token (SUPR0): grant converter burn rights (mint limit = 0, burn limit = total old supply).
    bytes memory _setLimitsOld = abi.encodeCall(IXERC20.setLimits, (address(_converter), 0, OLD_TOTAL_SUPPLY));

    // 2. New SUPR (SUPR1): grant converter mint rights (mint limit = max SUPR1 mintable, burn = 0).
    bytes memory _setLimitsNew = abi.encodeCall(IXERC20.setLimits, (address(_converter), _suprMintLimit, 0));

    // 3. BUILD (Lobsters): grant converter mint rights (mint limit = max BUILD mintable, burn = 0).
    bytes memory _setLimitsBuild = abi.encodeCall(IXERC20.setLimits, (address(_converter), _buildMintLimit, 0));

    // solhint-disable-next-line no-console
    console.log('SUPRConverter deployed:', address(_converter));
    // solhint-disable-next-line no-console
    console.log('--- ACTION 1: owner of OLD/SUPR0 token (%s) must call setLimits:', oldSupr);
    // solhint-disable-next-line no-console
    console.logBytes(_setLimitsOld);
    // solhint-disable-next-line no-console
    console.log('--- ACTION 2: owner of NEW/SUPR1 token (%s) must call setLimits:', newSupr);
    // solhint-disable-next-line no-console
    console.logBytes(_setLimitsNew);
    // solhint-disable-next-line no-console
    console.log('--- ACTION 3: owner of BUILD token (%s) must call setLimits:', build);
    // solhint-disable-next-line no-console
    console.logBytes(_setLimitsBuild);
    // solhint-disable-next-line no-console
    console.log('To close conversion: owners call setLimits(converter, 0, 0) on all three tokens');
  }
}

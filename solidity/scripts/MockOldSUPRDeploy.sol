// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// solhint-disable-next-line no-console
import {XERC20} from '@xERC20/contracts/XERC20.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/// @dev Testnet stand-in for the V1 SUPR token (CrosschainERC20 on mainnet).
///      Extends XERC20 with a permissionless mint so test accounts can be funded.
///      The deployer is set as owner (via factory param) and can call setLimits.
///      Do NOT deploy to mainnet.
contract MockOldSUPR is XERC20 {
  constructor(
    address _owner
  ) XERC20('Superseed', 'SUPR', _owner) {}

  /// @dev Permissionless test-only funding helper — bypasses the rate-limited mint().
  function freeMint(
    address to,
    uint256 amount
  ) public {
    _mint(to, amount);
  }
}

/**
 * @title MockOldSUPRDeploy
 * @notice Deploys a XERC20-based mock of the V1 SUPR token on testnets.
 *         The deployer becomes owner and can call setLimits to register the
 *         SUPRConverter as a burner once it is deployed.
 *
 * Usage:
 *   forge script solidity/scripts/MockOldSUPRDeploy.sol \
 *     --rpc-url $SEPOLIA_RPC --account $DEPLOYER_NAME --broadcast --verify
 *
 * After SUPRConverter is deployed, grant it burn rights:
 *   cast send <MockOldSUPR> "setLimits(address,uint256,uint256)" \
 *     <converter> 0 10000000000000000000000000000 \
 *     --rpc-url $SEPOLIA_RPC --account $DEPLOYER_NAME
 *
 * Copy the printed address into .env as OLD_TOKEN_ADDRESS.
 */
contract MockOldSUPRDeploy is Script {
  function run() public {
    // Broadcaster is provided via `--account <keystore>` (no raw private key in env).
    vm.startBroadcast();
    MockOldSUPR _mock = new MockOldSUPR(msg.sender);
    // Mint 1 000 000 000 tokens to the deployer for testing.
    _mock.freeMint(msg.sender, 1_000_000_000e18);
    vm.stopBroadcast();

    // solhint-disable-next-line no-console
    console.log('MockOldSUPR deployed to:', address(_mock));
    // Copy this address into .env as OLD_TOKEN_ADDRESS.
  }
}

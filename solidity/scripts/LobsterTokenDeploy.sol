// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// solhint-disable-next-line no-console
import {LobsterToken} from '../contracts/LobsterToken.sol';
import {XERC20Lockbox} from '@xERC20/contracts/XERC20Lockbox.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title LobsterTokenDeploy
 * @notice Deploys LobsterToken directly. Name and symbol are baked into the contract, so the
 *         only deploy-time inputs are the governor (final owner) and, where a canonical ERC20
 *         is wrapped, the lockbox base token.
 *
 *         The broadcaster is the token's immutable FACTORY (the only address able to call
 *         setLockbox) and its initial owner. The script deploys the lockbox while it still
 *         holds that role, then hands ownership to the governor. Bridge limits are configured
 *         afterwards by the owner via setLimits(bridge, mintLimit, burnLimit).
 *
 * Env vars (.env):
 *   GOVERNOR_ADDRESS     Address that will own the token after deployment (required)
 *   BASE_TOKEN_ADDRESS   Canonical ERC20 to wrap in a lockbox (optional; address(0) = none)
 *   IS_NATIVE_GAS_TOKEN  true to wrap the chain's native gas token instead of an ERC20 (optional)
 *
 * Usage:
 *   forge script solidity/scripts/LobsterTokenDeploy.sol --account <name> --rpc-url <rpc>
 *   add --broadcast --verify to broadcast.
 */
contract LobsterTokenDeploy is Script {
  error LobsterTokenDeploy_GovernorNotSet();

  function run() public {
    address _governor = vm.envAddress('GOVERNOR_ADDRESS');
    if (_governor == address(0)) revert LobsterTokenDeploy_GovernorNotSet();

    address _baseToken = vm.envOr('BASE_TOKEN_ADDRESS', address(0));
    bool _isNative = vm.envOr('IS_NATIVE_GAS_TOKEN', false);

    // Broadcaster is provided via `--account <keystore>` (no raw private key in env).
    vm.startBroadcast();

    // Deployer is the token's FACTORY (sole address allowed to set the lockbox) and initial
    // owner; ownership is handed to the governor below so the deployer EOA is never the owner.
    LobsterToken _token = new LobsterToken(msg.sender);

    address _lockbox;
    if (_baseToken != address(0) || _isNative) {
      _lockbox = address(new XERC20Lockbox(address(_token), _baseToken, _isNative));
      _token.setLockbox(_lockbox);
    }

    _token.transferOwnership(_governor);

    vm.stopBroadcast();

    // solhint-disable-next-line no-console
    console.log('LobsterToken:', address(_token));
    if (_lockbox != address(0)) {
      // solhint-disable-next-line no-console
      console.log('Lockbox:', _lockbox);
    }
    // solhint-disable-next-line no-console
    console.log('Owner (governor):', _governor);
    // solhint-disable-next-line no-console
    console.log('Register bridges: governor calls setLimits(bridge, mintLimit, burnLimit)');
  }
}

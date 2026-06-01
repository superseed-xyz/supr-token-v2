// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface IXERC20Factory {
  /**
   * @notice Emitted when a new XERC20 is deployed
   *
   * @param _xerc20 The address of the xerc20
   */
  event XERC20Deployed(address _xerc20);

  /**
   * @notice Emitted when a new XERC20Lockbox is deployed
   *
   * @param _lockbox The address of the lockbox
   */
  event LockboxDeployed(address _lockbox);

  /**
   * @notice Reverts when a non-owner attempts to call
   */
  error IXERC20Factory_NotOwner();

  /**
   * @notice Reverts when a lockbox is trying to be deployed from a malicious address
   */
  error IXERC20Factory_BadTokenAddress();

  /**
   * @notice Reverts when a lockbox is already deployed
   */
  error IXERC20Factory_LockboxAlreadyDeployed();

  /**
   * @notice Reverts when a the length of arrays sent is incorrect
   */
  error IXERC20Factory_InvalidLength();

  /**
   * @notice Deploys an XERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _minterLimits The array of minter limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of burning limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of burners that you are adding (optional, can be an empty array)
   * @param _owner The address that will own the token after deployment
   * @return _xerc20 The address of the xerc20
   */
  function deployXERC20(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    address _owner
  ) external returns (address _xerc20);

  /**
   * @notice Atomically deploys an XERC20 and its XERC20Lockbox, then transfers ownership
   *
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _minterLimits The array of minter limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of burning limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
   * @param _baseToken The address of the base token that you want to lock (address(0) if native)
   * @param _isNative Whether or not the base token is native
   * @param _owner The address that will own the token after deployment
   * @return _xerc20 The address of the xerc20
   * @return _lockbox The address of the lockbox
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
  ) external returns (address _xerc20, address payable _lockbox);

  /**
   * @notice Deploys an XERC20Lockbox contract using CREATE3
   *
   * @param _xerc20 The address of the xerc20 that you want to deploy a lockbox for
   * @param _baseToken The address of the base token that you want to lock
   * @param _isNative Whether or not the base token is native
   * @return _lockbox The address of the lockbox
   */
  function deployLockbox(
    address _xerc20,
    address _baseToken,
    bool _isNative
  ) external returns (address payable _lockbox);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IXERC20} from '../interfaces/IXERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title XERC20
 * @notice Forked from defi-wonderland/xERC20.
 */
contract XERC20 is ERC20, ERC20Permit, Ownable, IXERC20 {
  uint256 private constant _DURATION = 1 days;

  address public immutable FACTORY;
  address public lockbox;
  mapping(address => Bridge) public bridges;

  constructor(string memory _name, string memory _symbol, address _factory) ERC20(_name, _symbol) ERC20Permit(_name) {
    _transferOwnership(_factory);
    FACTORY = _factory;
  }

  function setLockbox(address _lockbox) public {
    if (msg.sender != FACTORY) revert IXERC20_NotFactory();
    lockbox = _lockbox;
    emit LockboxSet(_lockbox);
  }

  function setLimits(address _bridge, uint256 _mintingLimit, uint256 _burningLimit) external onlyOwner {
    if (_mintingLimit > (type(uint256).max / 2) || _burningLimit > (type(uint256).max / 2)) {
      revert IXERC20_LimitsTooHigh();
    }
    _changeMinterLimit(_bridge, _mintingLimit);
    _changeBurnerLimit(_bridge, _burningLimit);
    emit BridgeLimitsSet(_mintingLimit, _burningLimit, _bridge);
  }

  function mint(address _user, uint256 _amount) public virtual {
    _mintWithCaller(msg.sender, _user, _amount);
  }

  function burn(address _user, uint256 _amount) public virtual {
    if (msg.sender != _user) {
      _spendAllowance(_user, msg.sender, _amount);
    }
    _burnWithCaller(msg.sender, _user, _amount);
  }

  function mintingMaxLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = bridges[_bridge].minterParams.maxLimit;
  }

  function burningMaxLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = bridges[_bridge].burnerParams.maxLimit;
  }

  function mintingCurrentLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = _getCurrentLimit(
      bridges[_bridge].minterParams.currentLimit,
      bridges[_bridge].minterParams.maxLimit,
      bridges[_bridge].minterParams.timestamp,
      bridges[_bridge].minterParams.ratePerSecond
    );
  }

  function burningCurrentLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = _getCurrentLimit(
      bridges[_bridge].burnerParams.currentLimit,
      bridges[_bridge].burnerParams.maxLimit,
      bridges[_bridge].burnerParams.timestamp,
      bridges[_bridge].burnerParams.ratePerSecond
    );
  }

  function _useMinterLimits(address _bridge, uint256 _change) internal {
    uint256 _currentLimit = mintingCurrentLimitOf(_bridge);
    bridges[_bridge].minterParams.timestamp = block.timestamp;
    bridges[_bridge].minterParams.currentLimit = _currentLimit - _change;
  }

  function _useBurnerLimits(address _bridge, uint256 _change) internal {
    uint256 _currentLimit = burningCurrentLimitOf(_bridge);
    bridges[_bridge].burnerParams.timestamp = block.timestamp;
    bridges[_bridge].burnerParams.currentLimit = _currentLimit - _change;
  }

  function _changeMinterLimit(address _bridge, uint256 _limit) internal {
    uint256 _oldLimit = bridges[_bridge].minterParams.maxLimit;
    uint256 _currentLimit = mintingCurrentLimitOf(_bridge);
    bridges[_bridge].minterParams.maxLimit = _limit;
    bridges[_bridge].minterParams.currentLimit = _calculateNewCurrentLimit(_limit, _oldLimit, _currentLimit);
    bridges[_bridge].minterParams.ratePerSecond = _limit / _DURATION;
    bridges[_bridge].minterParams.timestamp = block.timestamp;
  }

  function _changeBurnerLimit(address _bridge, uint256 _limit) internal {
    uint256 _oldLimit = bridges[_bridge].burnerParams.maxLimit;
    uint256 _currentLimit = burningCurrentLimitOf(_bridge);
    bridges[_bridge].burnerParams.maxLimit = _limit;
    bridges[_bridge].burnerParams.currentLimit = _calculateNewCurrentLimit(_limit, _oldLimit, _currentLimit);
    bridges[_bridge].burnerParams.ratePerSecond = _limit / _DURATION;
    bridges[_bridge].burnerParams.timestamp = block.timestamp;
  }

  function _calculateNewCurrentLimit(
    uint256 _limit,
    uint256 _oldLimit,
    uint256 _currentLimit
  ) internal pure returns (uint256 _newCurrentLimit) {
    uint256 _difference;
    if (_oldLimit > _limit) {
      _difference = _oldLimit - _limit;
      _newCurrentLimit = _currentLimit > _difference ? _currentLimit - _difference : 0;
    } else {
      _difference = _limit - _oldLimit;
      _newCurrentLimit = _currentLimit + _difference;
    }
  }

  function _getCurrentLimit(
    uint256 _currentLimit,
    uint256 _maxLimit,
    uint256 _timestamp,
    uint256 _ratePerSecond
  ) internal view returns (uint256 _limit) {
    _limit = _currentLimit;
    if (_limit == _maxLimit) {
      return _limit;
    } else if (_timestamp + _DURATION <= block.timestamp) {
      _limit = _maxLimit;
    } else if (_timestamp + _DURATION > block.timestamp) {
      uint256 _timePassed = block.timestamp - _timestamp;
      uint256 _calculatedLimit = _limit + (_timePassed * _ratePerSecond);
      _limit = _calculatedLimit > _maxLimit ? _maxLimit : _calculatedLimit;
    }
  }

  function _burnWithCaller(address _caller, address _user, uint256 _amount) internal virtual {
    if (_caller != lockbox) {
      uint256 _currentLimit = burningCurrentLimitOf(_caller);
      if (_currentLimit < _amount) revert IXERC20_NotHighEnoughLimits();
      _useBurnerLimits(_caller, _amount);
    }
    _burn(_user, _amount);
  }

  function _mintWithCaller(address _caller, address _user, uint256 _amount) internal virtual {
    if (_caller != lockbox) {
      uint256 _currentLimit = mintingCurrentLimitOf(_caller);
      if (_currentLimit < _amount) revert IXERC20_NotHighEnoughLimits();
      _useMinterLimits(_caller, _amount);
    }
    _mint(_user, _amount);
  }
}

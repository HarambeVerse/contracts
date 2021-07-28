// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import { AccessControl } from '@openzeppelin/contracts/access/AccessControl.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

abstract contract DuckAccessControl is AccessControl, Ownable {
  /// @notice set minter role, ie staking contracts
  bytes32 public constant BURNER_ROLE = keccak256('BURNER_ROLE');

  /// @notice set dev role
  bytes32 public constant DEV_ROLE = keccak256('DEV_ROLE');

  /// @notice set minter role, ie staking contracts
  bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');

  /// @notice onlyBurner modifier
  modifier onlyBurner() {
    require(hasRole(BURNER_ROLE, msg.sender), 'DuckAccessControl: Only burner');
    _;
  }

  /// @notice setup a burner role can only be set by dev
  /// @param _burner burner address
  function setupBurner(address _burner) external onlyOwner {
    require(_isContract(_burner), 'DuckAccessControl: Burner can only be a contract');
    _setupRole(BURNER_ROLE, _burner);
  }

  /// @notice onlyDev modifier
  modifier onlyDev() {
    require(hasRole(DEV_ROLE, msg.sender), 'DuckAccessControl: Only dev');
    _;
  }

  /// @notice setup a dev role can only be set by dev
  /// @param _dev dev address
  function setupDev(address _dev) external onlyOwner {
    _setupRole(DEV_ROLE, _dev);
  }

  /// @notice onlyMinter modifier
  modifier onlyMinter() {
    require(hasRole(MINTER_ROLE, msg.sender), 'DuckAccessControl: Only minter');
    _;
  }

  /// @notice setup minter role can only be set by dev
  /// @param _minter minter address
  function setupMinter(address _minter) external onlyDev {
    _setupRole(MINTER_ROLE, _minter);
  }

  /// @notice assign owner to dev
  constructor() {
    _setupRole(DEV_ROLE, msg.sender);
  }

  /// @notice Check if an address is a contract
  function _isContract(address _addr) internal view returns (bool isContract_) {
    uint256 size;
    assembly {
      size := extcodesize(_addr)
    }
    isContract_ = size > 0;
  }
}

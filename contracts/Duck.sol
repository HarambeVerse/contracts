// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';

import { DuckAccessControl } from './DuckAccessControl.sol';
import { DuckBase } from './DuckBase.sol';

//import { console } from 'hardhat/console.sol';

//
//          ."'".
//      .-./ _=_ \.-.
//     {  (,(oYo),) }}
//     {{ |   "   |} }
//     { { \(---)/  }}
//     {{  }'-=-'{ } }
//     { { }._:_.{  }}
//     {{  } -:- { } }
//     {_{ }'==='{  _}
//    ((((\)     (/))))
//
//  ---Harambe 1999-2016---
/// @notice Duck the main utility token of the HarambeVerse eco-system.
contract Duck is DuckBase {
  using SafeMath for uint256;
  /// @notice owner => next valid nonce to submit with permit()
  mapping(address => uint256) public _nonces;

  mapping(address => mapping(uint256 => Checkpoint)) public _votingCheckpoints;

  mapping(address => uint256) public _votingCheckpointsCounts;

  bytes32 public DOMAIN_SEPARATOR;
  bytes public constant EIP712_REVISION = bytes('1');
  bytes32 internal constant EIP712_DOMAIN =
    keccak256(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
  bytes32 public constant PERMIT_TYPEHASH =
    keccak256(
      'Permit(address owner,address spender,uint256 _value,uint256 nonce,uint256 deadline)'
    );

  mapping(address => address) internal _votingDelegates;

  mapping(address => mapping(uint256 => Checkpoint))
    internal _propositionPowerCheckpoints;
  mapping(address => uint256) internal _propositionPowerCheckpointsCounts;

  mapping(address => address) internal _propositionPowerDelegates;

  /// @notice implements the permit function
  /// @param _owner the owner of the funds
  /// @param _spender the spender
  /// @param _value the amount
  /// @param _deadline the deadline timestamp, type(uint256).max for no deadline
  /// @param _v signature param
  /// @param _r signature param
  /// @param _s signature param
  function permit(
    address _owner,
    address _spender,
    uint256 _value,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external {
    require(_owner != address(0), 'DUCK: permit: Not correct owner');
    require(block.timestamp <= _deadline, 'DUCK: permit: deadline already passed');

    uint256 currentValidNonce = _nonces[_owner];
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        DOMAIN_SEPARATOR,
        keccak256(
          abi.encode(
            PERMIT_TYPEHASH,
            _owner,
            _spender,
            _value,
            currentValidNonce,
            _deadline
          )
        )
      )
    );

    require(_owner == ecrecover(digest, _v, _r, _s), 'DUCK: permit: invalid signature');
    _nonces[_owner] = currentValidNonce.add(1);
    _approve(_owner, _spender, _value);
  }

  /// @notice Writes a checkpoint before any operation involving transfer of value: _transfer, _mint and _burn
  /// - On _transfer, it writes checkpoints for both "from" and "to"
  /// - On _mint, only for _to
  /// - On _burn, only for _from
  /// @param _from the from address
  /// @param _to the to address
  /// @param _amount the amount to transfer
  ////
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal override {
    address votingFromDelegatee = _getDelegatee(_from, _votingDelegates);
    address votingToDelegatee = _getDelegatee(_to, _votingDelegates);

    _moveDelegatesByPower(
      votingFromDelegatee,
      votingToDelegatee,
      _amount,
      DelegationPower.Voting
    );

    address propPowerFromDelegatee = _getDelegatee(
      _from,
      _propositionPowerDelegates
    );
    address propPowerToDelegatee = _getDelegatee(
      _to,
      _propositionPowerDelegates
    );

    _moveDelegatesByPower(
      propPowerFromDelegatee,
      propPowerToDelegatee,
      _amount,
      DelegationPower.Proposition
    );
  }

  function _getDelegationDataByPower(DelegationPower delegationPower)
    internal
    view
    override
    returns (
      mapping(address => mapping(uint256 => Checkpoint)) storage checkpoints_,
      mapping(address => uint256) storage checkpointsCount_,
      mapping(address => address) storage delegates_
    )
  {
    if (delegationPower == DelegationPower.Voting) {
      checkpoints_ = _votingCheckpoints;
      checkpointsCount_ = _votingCheckpointsCounts;
      delegates_ = _votingDelegates;
    } else {
      checkpoints_ = _propositionPowerCheckpoints;
      checkpointsCount_ = _propositionPowerCheckpointsCounts;
      delegates_ = _propositionPowerDelegates;
    }
  }

  /// @notice Delegates power from signatory to `delegatee`
  /// @param delegatee The address to delegate votes to
  /// @param delegationPower the type of delegation (VOTING_POWER, PROPOSITION_POWER)
  /// @param nonce The contract state required to match the signature
  /// @param expiry The time at which to expire the signature
  /// @param _v The recovery byte of the signature
  /// @param _r Half of the ECDSA signature pair
  /// @param _s Half of the ECDSA signature pair
  function delegateByPowerBySig(
    address delegatee,
    DelegationPower delegationPower,
    uint256 nonce,
    uint256 expiry,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) public {
    bytes32 structHash = keccak256(
      abi.encode(
        DELEGATE_BY_POWER_TYPEHASH,
        delegatee,
        uint256(delegationPower),
        nonce,
        expiry
      )
    );
    bytes32 digest = keccak256(
      abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, structHash)
    );
    address signatory = ecrecover(digest, _v, _r, _s);
    require(signatory != address(0), 'DUCK: delegateByPowerBySig: invalid signature');
    require(nonce == _nonces[signatory]++, 'DUCK: delegateByPowerBySig: invalid nonce');
    require(block.timestamp <= expiry, 'DUCK: delegateByPowerBySig: invalid expiration');
    _delegateByPower(signatory, delegatee, delegationPower);
  }

  /// @notice Delegates power from signatory to `delegatee`
  /// @param delegatee The address to delegate votes to
  /// @param nonce The contract state required to match the signature
  /// @param expiry The time at which to expire the signature
  /// @param _v The recovery byte of the signature
  /// @param _r Half of the ECDSA signature pair
  /// @param _s Half of the ECDSA signature pair
  function delegateBySig(
    address delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) public {
    bytes32 structHash = keccak256(
      abi.encode(DELEGATE_TYPEHASH, delegatee, nonce, expiry)
    );
    bytes32 digest = keccak256(
      abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, structHash)
    );
    address signatory = ecrecover(digest, _v, _r, _s);
    require(signatory != address(0), 'DUCK: delegateByPowerBySig: invalid signature');
    require(nonce == _nonces[signatory]++, 'DUCK: delegateByPowerBySig: invalid nonce');
    require(block.timestamp <= expiry, 'DUCK: delegateByPowerBySig: invalid expiration');
    _delegateByPower(signatory, delegatee, DelegationPower.Voting);
    _delegateByPower(signatory, delegatee, DelegationPower.Proposition);
  }
}

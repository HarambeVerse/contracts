// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';

import { ERC20 } from './open-zeppelin/ERC20.sol';

import { IDuckVesting } from './interfaces/IDuckVesting.sol';

import { DuckAccessControl } from './DuckAccessControl.sol';
import { DuckBase } from './DuckBase.sol';

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

  string internal constant NAME = 'Duck Token';
  string internal constant SYMBOL = 'DUCK';
  uint8 internal constant DECIMALS = 18;

  uint256 public constant VESTING_AMOUNT = 50 * 1000 * 10**18;
  uint256 public constant INIT_AMOUNT = 10 * 10**18;

  bytes32 public DOMAIN_SEPARATOR = keccak256(
    abi.encode(
      EIP712_DOMAIN,
      keccak256(bytes(NAME)),
      keccak256(EIP712_REVISION),
      block.chainid,
      address(this)
    )
  );

  bytes public constant EIP712_REVISION = bytes('1');
  bytes32 internal constant EIP712_DOMAIN =
    keccak256(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
  bytes32 public constant PERMIT_TYPEHASH =
    keccak256(
      'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );

  mapping(address => uint256) public _nonces;

  mapping(address => mapping(uint256 => Checkpoint)) public _votingCheckpoints;
  mapping(address => uint256) public _votingCheckpointsCounts;
  mapping(address => address) internal _votingDelegates;

  mapping(address => mapping(uint256 => Checkpoint))
    internal _propositionPowerCheckpoints;
  mapping(address => uint256) internal _propositionPowerCheckpointsCounts;
  mapping(address => address) internal _propositionPowerDelegates;

  constructor() ERC20(NAME, SYMBOL) {
    _mint(msg.sender, INIT_AMOUNT);
  }

  /// @notice initialises vesting for team wallet
  /// @param _beneficiary address to which tokens will be granted
  /// @param _totalAmount the total amount of tokens deposited
  /// @param _vestingAmount numbers from total amount to be vested
  /// @param _startDay start day of the besting
  /// @param _cliffDuration duration of the cliff, with respect to the grant start day, in days
  /// @param _duration duration of the vesting schedule, with respect to the grant start day, in days
  /// @param _interval number of days between vesting increases
  function initVesting(
    address _vestingAddress,
    address _beneficiary,
    uint256 _totalAmount,
    uint256 _vestingAmount,
    uint32 _startDay,
    uint32 _duration,
    uint32 _cliffDuration,
    uint32 _interval
  ) external virtual onlyOwner {
    _mint(address(this), VESTING_AMOUNT);

    IDuckVesting duckVesting = IDuckVesting(_vestingAddress);
    duckVesting.grantVestingTokens(
      _beneficiary,
      _totalAmount,
      _vestingAmount,
      _startDay,
      _duration,
      _cliffDuration,
      _interval,
      false
    );
  }

  /// @notice mints an amount to an account only can be ran by minter
  /// @param _to The address to mint to
  /// @param _amount The amount to mint
  function mint(address _to, uint256 _amount) external virtual onlyMinter {
    _mint(_to, _amount);
  }

  /// @notice burns an amount to an account only can be ran by burner
  /// @param _from The address to burn from
  /// @param _amount The amount to burn
  function burn(address _from, uint256 _amount) external virtual onlyBurner {
    _burn(_from, _amount);
  }

  /// @notice implements the permit function
  /// @param _owner the owner of the funds
  /// @param _spender the _spender
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
    require(_owner != address(0), 'DUCK:: owner invalid');
    require(block.timestamp <= _deadline, 'Duck:: invalid deadline');
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

    require(
      _owner == ecrecover(digest, _v, _r, _s),
      'Duck:: invalid signature'
    );
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

  /// @notice get delegation data by power
  /// @param _power the power querying by from
  function _getDelegationDataByPower(DelegationPower _power)
    internal
    view
    override
    returns (
      mapping(address => mapping(uint256 => Checkpoint)) storage checkpoints_,
      mapping(address => uint256) storage checkpointsCount_,
      mapping(address => address) storage delegates_
    )
  {
    if (_power == DelegationPower.Voting) {
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
  /// @param _delegatee The address to delegate votes to
  /// @param _power the power of delegation
  /// @param _nonce The contract state required to match the signature
  /// @param _expiry The time at which to expire the signature
  /// @param _v The recovery byte of the signature
  /// @param _r Half of the ECDSA signature pair
  /// @param _s Half of the ECDSA signature pair
  function delegateByPowerBySig(
    address _delegatee,
    DelegationPower _power,
    uint256 _nonce,
    uint256 _expiry,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) public {
    bytes32 structHash = keccak256(
      abi.encode(
        DELEGATE_BY_POWER_TYPEHASH,
        _delegatee,
        uint256(_power),
        _nonce,
        _expiry
      )
    );
    bytes32 digest = keccak256(
      abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, structHash)
    );
    address signatory = ecrecover(digest, _v, _r, _s);
    require(
      signatory != address(0),
      'DUCK: delegateByPowerBySig: invalid signature'
    );
    require(
      _nonce == _nonces[signatory]++,
      'DUCK: delegateByPowerBySig: invalid nonce'
    );
    require(
      block.timestamp <= _expiry,
      'DUCK: delegateByPowerBySig: invalid expiration'
    );
    _delegateByPower(signatory, _delegatee, _power);
  }

  /// @notice Delegates power from signatory to `_delegatee`
  /// @param _delegatee The address to delegate votes to
  /// @param _nonce The contract state required to match the signature
  /// @param _expiry The time at which to expire the signature
  /// @param _v The recovery byte of the signature
  /// @param _r Half of the ECDSA signature pair
  /// @param _s Half of the ECDSA signature pair
  function delegateBySig(
    address _delegatee,
    uint256 _nonce,
    uint256 _expiry,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) public {
    bytes32 structHash = keccak256(
      abi.encode(DELEGATE_TYPEHASH, _delegatee, _nonce, _expiry)
    );
    bytes32 digest = keccak256(
      abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, structHash)
    );
    address signatory = ecrecover(digest, _v, _r, _s);
    require(
      signatory != address(0),
      'DUCK: delegateByPowerBySig: invalid signature'
    );
    require(
      _nonce == _nonces[signatory]++,
      'DUCK: delegateByPowerBySig: invalid nonce'
    );
    require(
      block.timestamp <= _expiry,
      'DUCK: delegateByPowerBySig: invalid expiration'
    );

    _delegateByPower(signatory, _delegatee, DelegationPower.Voting);
    _delegateByPower(signatory, _delegatee, DelegationPower.Proposition);
  }
}

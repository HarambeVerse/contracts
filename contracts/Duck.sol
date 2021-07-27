// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';

import { DuckAccessControl } from './DuckAccessControl.sol';

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
contract Duck is ERC20('Duck', 'DUCK'), DuckAccessControl {
  using SafeMath for uint256;
  /// @notice A record of each accounts delegate
  mapping(address => address) internal _delegates;

  /// @notice total supply
  uint256 private _totalSupply;

  /// @notice A checkpoint for marking number of votes from a given block
  struct Checkpoint {
    uint32 fromBlock;
    uint256 votes;
  }

  /// @notice A record of votes checkpoints for each account, by index
  mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

  /// @notice The number of checkpoints for each account
  mapping(address => uint32) public numCheckpoints;

  /// @notice The EIP-712 typehash for the contract's domain
  bytes32 public constant DOMAIN_TYPEHASH =
    keccak256(
      'EIP712Domain(string name,uint256 chainId,address verifyingContract)'
    );

  /// @notice The EIP-712 typehash for the delegation struct used by the contract
  bytes32 public constant DELEGATION_TYPEHASH =
    keccak256('Delegation(address _delegatee,uint256 _nonce,uint256 _expiry)');

  /// @notice A record of states for signing / validating signatures
  mapping(address => uint256) public nonces;

  /// @notice An event thats emitted when an account changes its delegate
  event DelegateChanged(
    address indexed _delegator,
    address indexed _prviousDelegate,
    address indexed _delegate
  );

  /// @notice An event thats emitted when a delegate account's vote balance changes
  event DelegateVotesChanged(
    address indexed _delegate,
    uint256 _previousBalance,
    uint256 _balance
  );

  /// @notice Emitted when transferFrom has been successful
  event TransferFrom(
    address indexed _from,
    address indexed _to,
    uint256 _value
  );

  /// @notice See {ERC20-transfer}.
  function transfer(address _to, uint256 _amount)
    public
    virtual
    override
    returns (bool)
  {
    _transfer(_msgSender(), _to, _amount);
    _moveDelegates(_delegates[_msgSender()], _delegates[_to], _amount);

    emit Transfer(_msgSender(), _to, _amount);
    return true;
  }

  /// @notice See {ERC20-transferFrom}.
  function transferFrom(
    address _from,
    address _to,
    uint256 _amount
  ) public virtual override returns (bool) {
    _transfer(_from, _to, _amount);
    _moveDelegates(_delegates[_from], _delegates[_to], _amount);
    _approve(
      _from,
      _msgSender(),
      allowance(_from, _msgSender()).sub(
        _amount,
        'DUCK: transfer amount exceeds allowance'
      )
    );

    emit TransferFrom(_msgSender(), _to, _amount);
    return true;
  }

  /// @notice mints an amount to an account only can be ran by minter
  /// @param _to The address to mint to
  /// @param _amount The amount to mint
  function mint(address _to, uint256 _amount) public virtual onlyMinter {
    _mint(_to, _amount);
    _moveDelegates(address(0), _delegates[_to], _amount);
  }

  /// @notice burn an amount from an account to burner address only can be ran by burner
  /// @param _from The address to mint to
  /// @param _amount The amount to mint
  function burn(address _from, uint256 _amount) public virtual onlyBurner {
    _burn(_from, _amount);
    _moveDelegates(address(0), _delegates[_from], _amount);
  }

  /// @notice Delegate votes from `msg.sender` to `_delegatee`
  /// @param _delegatee The address to delegate votes to
  function delegate(address _delegatee) external virtual {
    return _delegate(msg.sender, _delegatee);
  }

  /// @notice Delegates votes from signatory to `_delegatee`
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
  ) external virtual {
    bytes32 domainSeparator = keccak256(
      abi.encode(
        DOMAIN_TYPEHASH,
        keccak256(bytes(name())),
        _getChainId(),
        address(this)
      )
    );

    bytes32 structHash = keccak256(
      abi.encode(DELEGATION_TYPEHASH, _delegatee, _nonce, _expiry)
    );

    bytes32 digest = keccak256(
      abi.encodePacked('\x19\x01', domainSeparator, structHash)
    );

    address signatory = ecrecover(digest, _v, _r, _s);
    require(signatory != address(0), 'DUCK: delegateBySig: invalid signature');
    require(_nonce == nonces[signatory]++, 'DUCK: delegateBySig: invalid nonce');
    require(
      block.timestamp <= _expiry,
      'DUCK: delegateBySig: signature expired'
    );
    return _delegate(signatory, _delegatee);
  }

  /// @notice Gets the current votes balance for `account`
  /// @param _for The address to get votes balance
  /// @return The number of current votes for `account`
  function getCurrentVotes(address _for) external view returns (uint256) {
    uint32 nCheckpoints = numCheckpoints[_for];
    return nCheckpoints > 0 ? checkpoints[_for][nCheckpoints - 1].votes : 0;
  }

  /// @notice Determine the prior number of votes for an account as of a block number
  /// @notice Block number must be a finalized block or else this function will revert to prevent misinformation.
  /// @param _for The address of the account to check
  /// @param _blockNumber The block number to get the vote balance at
  /// @return The number of votes the account had as of the given block
  function getPriorVotes(address _for, uint256 _blockNumber)
    public
    view
    returns (uint256)
  {
    require(
      _blockNumber < block.number,
      'DUCK: getPriorVotes: not yet determined'
    );

    uint32 nCheckpoints = numCheckpoints[_for];
    if (nCheckpoints == 0) {
      return 0;
    }

    // First check most recent balance
    if (checkpoints[_for][nCheckpoints - 1].fromBlock <= _blockNumber) {
      return checkpoints[_for][nCheckpoints - 1].votes;
    }

    // Next check implicit zero balance
    if (checkpoints[_for][0].fromBlock > _blockNumber) {
      return 0;
    }

    uint32 lower = 0;
    uint32 upper = nCheckpoints - 1;
    while (upper > lower) {
      uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
      Checkpoint memory cp = checkpoints[_for][center];
      if (cp.fromBlock == _blockNumber) {
        return cp.votes;
      } else if (cp.fromBlock < _blockNumber) {
        lower = center;
      } else {
        upper = center - 1;
      }
    }
    return checkpoints[_for][lower].votes;
  }

  /// @notice Set `delegatee` for `delegator`
  /// @param _delegator The address of the delegator account
  /// @param _delegatee The address of the delegatee account
  function _delegate(address _delegator, address _delegatee) internal virtual {
    address currentDelegate = _delegates[_delegator];
    uint256 delegatorBalance = balanceOf(_delegator); // balance of underlying KIBs (not scaled);
    _delegates[_delegator] = _delegatee;

    emit DelegateChanged(_delegator, currentDelegate, _delegatee);

    _moveDelegates(currentDelegate, _delegatee, delegatorBalance);
  }

  /// @notice Move delegates
  /// @param _srcRep The address of the src representative
  /// @param _dstRep The address of the dst representative
  /// @param _amount The number of tokens
  function _moveDelegates(
    address _srcRep,
    address _dstRep,
    uint256 _amount
  ) internal virtual {
    if (_srcRep != _dstRep && _amount > 0) {
      if (_srcRep != address(0)) {
        // decrease old representative
        uint32 srcRepNum = numCheckpoints[_srcRep];
        uint256 srcRepOld = srcRepNum > 0
          ? checkpoints[_srcRep][srcRepNum - 1].votes
          : 0;
        uint256 srcRepNew = srcRepOld.sub(_amount);
        _writeCheckpoint(_srcRep, srcRepNum, srcRepOld, srcRepNew);
      }

      if (_dstRep != address(0)) {
        // increase new representative
        uint32 dstRepNum = numCheckpoints[_dstRep];
        uint256 dstRepOld = dstRepNum > 0
          ? checkpoints[_dstRep][dstRepNum - 1].votes
          : 0;
        uint256 dstRepNew = dstRepOld.add(_amount);
        _writeCheckpoint(_dstRep, dstRepNum, dstRepOld, dstRepNew);
      }
    }
  }

  /// @notice Write checkpoint
  /// @param _delegatee The address of the _delegatee
  /// @param _nCheckpoints number of checkpoints
  /// @param _oldVotes The number of old votes
  /// @param _newVotes The number of new votes
  function _writeCheckpoint(
    address _delegatee,
    uint32 _nCheckpoints,
    uint256 _oldVotes,
    uint256 _newVotes
  ) internal virtual {
    uint32 blockNumber = _safe32(
      block.number,
      'DUCK: _writeCheckpoint: block number exceeds 32 bits'
    );

    if (
      _nCheckpoints > 0 &&
      checkpoints[_delegatee][_nCheckpoints - 1].fromBlock == blockNumber
    ) {
      checkpoints[_delegatee][_nCheckpoints - 1].votes = _newVotes;
    } else {
      checkpoints[_delegatee][_nCheckpoints] = Checkpoint(
        blockNumber,
        _newVotes
      );
      numCheckpoints[_delegatee] = _nCheckpoints + 1;
    }

    emit DelegateVotesChanged(_delegatee, _oldVotes, _newVotes);
  }

  function _safe32(uint256 _number, string memory _message)
    internal
    pure
    returns (uint32 number_)
  {
    require(_number < 2**32, _message);
    number_ = uint32(_number);
  }

  function _getChainId() internal view returns (uint256 chainId_) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    chainId_ = chainId;
  }
}

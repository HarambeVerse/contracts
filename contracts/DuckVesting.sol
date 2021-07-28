// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { AccessControl } from '@openzeppelin/contracts/access/AccessControl.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract DuckVesting is Ownable, AccessControl {
  using SafeMath for uint256;

  /// @notice 1000 years in days for sanity checking
  /// rounded up from https://www.unitsconverters.com/en/Thousandyears-To-Day/Unittounit-5987-97
  uint32 private constant THOUSAND_YEARS_DAYS = 365243;
  /// @notice ten years in days 1000 days by 100
  uint32 private constant TEN_YEARS_DAYS = THOUSAND_YEARS_DAYS / 100;

  /// @notice set GRANTOR role, this will be for contracts/accounts
  /// that can set a vesting schedule
  bytes32 public constant GRANTOR = keccak256('GRANTOR');

  /// @notice the amount of seconds in a day
  uint32 private constant SECONDS_PER_DAY = 24 * 60 * 60;

  /// @notice vesting schedule struct for schedule mapping
  /// @param isValid true if an entry exists and is valid
  /// @param isRevocable true if the vesting option is revocable (a gift), false if irrevocable (purchased)
  /// @param cliffDuration duration of the cliff, with respect to the grant start day, in days
  /// @param duration duration of the vesting schedule, with respect to the grant start day, in days
  /// @param interval duration in days of the vesting interval
  struct VestingSchedule {
    bool isValid;
    bool isRevocable;
    uint32 cliffDuration;
    uint32 duration;
    uint32 interval;
  }

  /// @notice token grant structure
  /// @param isActive true if this vesting entry is active and in-effect entry
  /// @param wasRevoked true if this vesting schedule was revoked
  /// @param startDay start day of the grant, in days since the UNIX epoch (start of day)
  /// @param amount total number of tokens that vest
  /// @param vestingLocation address of wallet that is holding the vesting schedule
  /// @param grantor grantor that made the grant
  struct TokenGrant {
    bool isActive;
    bool wasRevoked;
    uint32 startDay;
    uint256 amount;
    address vestingLocation;
    address grantor;
  }

  /// @notice onlyGrantor modifier
  modifier onlyGrantor() {
    require(
      hasRole(GRANTOR, msg.sender),
      'DuckAccessControl: Only vesting grantor'
    );
    _;
  }

  /// @notice onlyGrantOrBeneficiary modifier
  /// @param _beneficiary address to which tokens have been granted
  modifier onlyGrantOrBeneficiary(address _beneficiary) {
    require(
      hasRole(GRANTOR, msg.sender) || _tokenGrants[_beneficiary].isActive,
      'DuckAccessControl: Only vesting grantor beneficiary'
    );
    _;
  }

  /// @param _beneficiary address to which tokens have been granted
  /// @param _amount amount attempting to claim
  modifier onlyIfFundsAvailableNow(address _beneficiary, uint256 _amount) {
    require(
      _fundsAreAvailableOn(_beneficiary, amount, today()),
      balanceOf(account) < amount
        ? 'DuckAccessControl: insufficient funds'
        : 'DuckAccessControl: insufficient vested funds'
    );
    _;
  }

  /// @notice the schedules records stored in contract
  mapping(address => VestingSchedule) private _vestingSchedules;
  /// @notice the grants for tokens stored in contract
  mapping(address => TokenGrant) private _tokenGrants;
  /// @notice tracks amount to be paid by vesting to beneficiary
  mapping(address => uint256) private _beneficiaryAllowance;
  /// @notice the reference to the duck token
  SafeERC20 public duckToken;

  /// @notice the initiation of the vesting contract
  /// @param _duckTokenAddress the address for the duck token
  constructor(address _duckTokenAddress) public {
    duckToken = SafeERC20(_duckTokenAddress);
  }

  /// @notice setup a burner role can only be set by dev
  /// @param _scheduler scheduler address
  function setupGrantor(address _scheduler) external onlyOwner {
    _setupRole(GRANTOR, _scheduler);
  }

  /// @notice grants tokens to a beneficiary account
  /// @param _beneficiary address to which tokens will be granted
  /// @param _totalAmount the total amount of tokens deposited
  /// @param _vestingAmount numbers from total amount to be vested
  /// @param _startDay start day of the besting
  /// @param _cliffDuration duration of the cliff, with respect to the grant start day, in days
  /// @param _duration duration of the vesting schedule, with respect to the grant start day, in days
  /// @param _interval number of days between vesting increases
  /// @param _isRevocable whether or not the grant is revocable
  function grantVestingTokens(
    address _beneficiary,
    uint256 _totalAmount,
    uint256 _vestingAmount,
    uint32 _startDay,
    uint32 _duration,
    uint32 _cliffDuration,
    uint32 _interval,
    bool _isRevocable
  ) external onlyGrantor returns (bool done_) {
    require(
      !_tokenGrants[_beneficiary].isActive,
      'DuckVesting: _grantVestingTokens: grant already exists'
    );
    _setVestingSchedule(
      _beneficiary,
      _cliffDuration,
      _duration,
      _interval,
      _isRevocable
    );
    _grantVestingTokens(
      _beneficiary,
      _totalAmount,
      _vestingAmount,
      _startDay,
      msg.sender
    );

    done_ = true;
  }

  /// @notice operation to establish a vesting schedule
  /// @param _beneficiary address of wallet to store against the vesting schedule
  /// @param _cliffDuration duration of the cliff, with respect to the grant start day, in days
  /// @param _duration duration of the vesting schedule, with respect to the grant start day, in days
  /// @param _interval number of days between vesting increases
  /// @param _isRevocable whether or not the grant is revocable
  function _setVestingSchedule(
    address _beneficiary,
    uint32 _cliffDuration,
    uint32 _duration,
    uint32 _interval,
    bool _isRevocable
  ) internal returns (bool done_) {
    require(
      _duration > 0 &&
        _duration <= TEN_YEARS_DAYS &&
        _cliffDuration < _duration &&
        _interval >= 1,
      'DuckVesting: _setVestingSchedule: invalid schedule'
    );

    require(
      _duration % _interval == 0 && _cliffDuration % _duration == 0,
      'DuckVesting: _setVestingSchedule: invalid durations'
    );

    _vestingSchedules[_beneficiary] = VestingSchedule(
      true,
      _isRevocable,
      _cliffDuration,
      _duration,
      _interval
    );

    emit VestingScheduleCreated(
      _beneficiary,
      _cliffDuration,
      _duration,
      _interval,
      _isRevocable
    );

    done_ = true;
  }

  /// @notice check if account has a vesting schedule assigned
  /// @param _account the account checking
  function _hasVestingSchedule(address _account)
    internal
    view
    returns (bool valid_)
  {
    valid_ = _vestingSchedules[_account].isValid;
  }

  /// @notice grants tokens to a beneficiary account
  /// @param _beneficiary address to which tokens will be granted
  /// @param _totalAmount the total amount of tokens deposited
  /// @param _vestingAmount numbers from total amount to be vested
  /// @param _startDay start day of the besting
  /// @param _grantor granter performing the grant
  function _grantVestingTokens(
    address _beneficiary,
    uint256 _totalAmount,
    uint256 _vestingAmount,
    uint32 _startDay,
    address _grantor
  ) internal returns (bool done_) {
    require(
      !_tokenGrants[_beneficiary].isActive,
      'DuckVesting: _grantVestingTokens: grant already exists'
    );

    require(
      vestingAmount <= totalAmount &&
        vestingAmount > 0 &&
        startDay >= block.timestamp,
      'DuckVesting: _grantVestingTokens: invalid vesting params'
    );

    require(_hasVestingSchedule(_beneficiary), 'no such vesting schedule');
    duckToken.safeTransferFrom(_grantor, address(this), _totalAmount);
    _beneficiaryAllowance[_beneficiary] = _totalAmount;

    _tokenGrants[_beneficiary] = TokenGrant(
      true,
      false,
      _startDay,
      _vestingAmount,
      _vestingLocation,
      _grantor
    );

    emit VestingTokensGranted(
      beneficiary,
      vestingAmount,
      startDay,
      vestingLocation,
      grantor
    );

    done_ = true;
  }

  /// @notice gets today
  function today() external view returns (uint32 today_) {
    today_ = uint32(block.timestamp / SECONDS_PER_DAY);
  }

  /// @notice to switch between today if _onDayOrToday is 0 or specific day
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  function _effectiveDay(uint32 _onDayOrToday)
    internal
    view
    returns (uint32 effectiveDay_)
  {
    effectiveDay_ = _onDayOrToday == 0 ? today() : _onDayOrToday;
  }

  /// @notice gets amount that has not been vested to account
  /// @param _beneficiary address to which tokens have been granted
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  function _getNotVestedAmount(address _beneficiary, uint32 _onDayOrToday)
    internal
    view
    returns (uint256 notVested_)
  {
    TokenGrant storage grant = _tokenGrants[_beneficiary];
    VestingSchedule storage vesting = _vestingSchedules[_beneficiary];
    uint32 onDay = _effectiveDay(_onDayOrToday);

    if (!grant.isActive || onDay < grant.startDay + vesting.cliffDuration) {
      notVested_ = grant.amount;
    } else if (onDay >= grant.startDay + vesting.duration) {
      notVested_ = uint256(0);
    } else {
      uint32 daysVested = onDay - grant.startDay;
      uint32 effectiveDaysVested = (daysVested / vesting.interval) *
        vesting.interval;

      uint256 vested = grant.amount.mul(effectiveDaysVested).div(
        vesting.duration
      );
      notVested_ = grant.amount.sub(vested);
    }
  }

  /// @notice gets available amount based on allowance
  /// @param _beneficiary address to which tokens have been granted
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  function _getAvailableAmount(address _beneficiary, uint32 _onDayOrToday)
    internal
    view
    returns (uint256 available_)
  {
    uint256 totalTokens = _beneficiaryAllowance[_beneficiary];
    available_ = totalTokens.sub(
      _getNotVestedAmount(_beneficiary, _onDayOrToday)
    );
  }

  /// @notice gets available amount based on allowance
  /// @param _beneficiary address to which tokens have been granted
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  function vestingForAccountAsOf(address _beneficiary, uint32 _onDayOrToday)
    external
    view
    onlyGrantOrBeneficiary(_beneficiary)
    returns (
      uint256 amountVested_,
      uint256 amountNotVested_,
      uint256 amountOfGrant_,
      uint32 vestStartDay_,
      uint32 vestDuration_,
      uint32 cliffDuration_,
      uint32 vestIntervalDays_,
      bool isActive_,
      bool wasRevoked_
    )
  {
    TokenGrant storage grant = _tokenGrants[_beneficiary];
    VestingSchedule storage vesting = _vestingSchedules[_beneficiary];
    uint256 notVestedAmount = _getNotVestedAmount(_beneficiary, _onDayOrToday);
    uint256 grantAmount = grant.amount;

    amountVested_ = grantAmount.sub(notVestedAmount);
    amountNotVested_ = notVestedAmount;
    amountOfGrant_ = grantAmount;
    vestStartDay_ = grant.startDay;
    vestDuration_ = vesting.duration;
    cliffDuration_ = vesting.cliffDuration;
    vestIntervalDays_ = vesting.interval;
    isActive_ = grant.isActive;
    wasRevoked_ = grant.wasRevoked;
  }

  /// @notice gets available amount based on allowance from current sender
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  function vestingAsOf(uint32 _onDayOrToday)
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint32,
      uint32,
      uint32,
      uint32,
      bool,
      bool
    )
  {
    return vestingForAccountAsOf(msg.sender, _onDayOrToday);
  }

  /// @notice checks if the account has sufficient funds available to cover the given amount
  /// @param _beneficiary address to which tokens have been granted
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  /// @param _amount amount attempting to claim
  function _fundsAreAvailableOn(
    address _beneficiary,
    uint32 _onDayOrToday,
    uint256 _amount
  ) internal view returns (bool isAvailable_) {
    isAvailable_ = _amount <= _getAvailableAmount(account, _onDayOrToday);
  }

  /// @notice revoke beneficiary and send back to grantor
  /// @param _beneficiary address to which tokens have been granted
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  function revokeGrant(address _beneficiary, uint32 _onDayOrToday)
    external
    onlyGrantor
    returns (bool done_)
  {
    TokenGrant storage grant = _tokenGrants[_beneficiary];
    VestingSchedule storage vesting = _vestingSchedules[_beneficiary];
    uint256 notVestedAmount;

    require(
      msg.sender == owner() || msg.sender == grant.grantor,
      'DuckVesting: not allowed'
    );
    require(grant.isActive, 'DuckVesting: no active grant');
    require(vesting.isRevocable, 'DuckVesting: irrevocable');
    require(_onDayOrToday <= grant.startDay + vesting.duration, 'DuckVesting: no effect');
    require(_onDayOrToday >= today(), 'DuckVesting: cannot revoke vested holdings');

    notVestedAmount = _getNotVestedAmount(_beneficiary, _onDayOrToday);

    duckToken.safeTransfer(grant.grantor, notVestedAmount);

    _tokenGrants[_beneficiary].wasRevoked = true;
    _tokenGrants[_beneficiary].isActive = false;

    emit GrantRevoked(_beneficiary, _onDayOrToday);
    done_ = true;
  }

  /// @notice allows beneficiary to withdraw available funds.
  function withdraw(uint256 _value) external onlyIfFundsAvailableNow(msg.sender, value) returns (bool done_) {
    done_ = duckToken.safeTransfer(msg.sender, _value);
  }
}

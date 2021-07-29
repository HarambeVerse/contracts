// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IDuckVesting {
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
  ) external returns (bool done_);


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
    );

  /// @notice revoke beneficiary and send back to grantor
  /// @param _beneficiary address to which tokens have been granted
  /// @param _onDayOrToday the day to check for, in days since the UNIX epoch
  function revokeGrant(address _beneficiary, uint32 _onDayOrToday)
    external
    returns (bool done_);

  /// @notice allows beneficiary to withdraw available funds.
  function withdraw(uint256 _value)
    external
    returns (bool done_);
}

pragma solidity 0.8.4;

interface IDuck {
  function mint(address _to, uint256 _amount) external virtual;
}

contract DuckMinter {
  IDuck internal duck;

  constructor(address _duck) {
    duck = IDuck(_duck);
  }

  function mint(address _to, uint256 _amount) external virtual {
    duck.mint(_to, _amount);
  }
}

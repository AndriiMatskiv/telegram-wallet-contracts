// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TwToken is ERC20, Ownable {
  uint256 constant public MAX_SUPPLY = 1000000000 ether;
  uint256 constant public INITIAL_SUPPLY = 500000000 ether;

  constructor() ERC20("Tw Token", "TWT") {
    _mint(_msgSender(), INITIAL_SUPPLY);
  }

  function mint(address to_, uint256 amount_) external onlyOwner {
    require(totalSupply() + amount_ <= MAX_SUPPLY, "TwToken::mint Max supply reached");
    _mint(to_, amount_);
  }
}

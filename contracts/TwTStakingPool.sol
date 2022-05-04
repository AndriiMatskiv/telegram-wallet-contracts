// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

//IN PROGRESS
contract TwtStakingPool is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  struct PoolInfo {
    IERC20 token;
    uint256 rewardRate;
    uint256 minRewardStake;
    uint256 maxBonus;
    uint256 bonusDuration;
    uint256 bonusRate;
  }

  uint256 public bonusDecimals;
  uint256 public rewardDecimals;

  struct UserInfo {
    uint256 staked;
    uint256 balance;
    uint256 lastBonus;
    uint256 lastUpdated;
  }

  PoolInfo[] public poolInfo;
  mapping (uint256 => mapping (address => UserInfo)) public userInfo;

  uint256 public totalSupply;

  IERC20 public twtToken;

  event EthWithdrawn(uint256 amount);

  event RewardSet(uint256 rewardRate, uint256 minRewardStake);
  event BonusesSet(uint256 maxBonus, uint256 bonusDuration);
  event TwtTokenSet(address token);
  event RateToEthSet(uint256 rateToEth);

  event TokensStaked(address payer, uint256 amount, uint256 timestamp);
  event TokensWithdrawn(address owner, uint256 amount, uint256 timestamp);

  constructor(address twtToken_) {
    require(twtToken_ != address(0), "TwtStakingPool: twtToken is zero address");
    twtToken = IERC20(twtToken_);
  }
  
  modifier balanceUpdate(uint256 pId, address _owner) {
    uint256 duration = block.timestamp.sub(lastUpdated[_owner]);
    uint256 reward = calculateReward(_owner, staked[_owner], duration);
    
    balances[_owner] = balances[_owner].add(reward);
    lastUpdated[_owner] = block.timestamp;
    lastBonus[_owner] = Math.min(maxBonus, lastBonus[_owner].add(bonusRate.mul(duration)));
    _;
  }

  function getRewardByDuration(address _owner, uint256 _amount, uint256 _duration) 
    public view returns(uint256) {
      return calculateReward(_owner, _amount, _duration);
  }

  function getStaked(address _owner) 
    public view returns(uint256) {
      return staked[_owner];
  }
  
  function balanceOf(address _owner)
    public view returns(uint256) {
      uint256 reward = calculateReward(_owner, staked[_owner], block.timestamp.sub(lastUpdated[_owner]));
      return balances[_owner].add(reward);
  }

  function getCurrentBonus(address _owner) 
    public view returns(uint256) {
      if(staked[_owner] == 0) {
        return 0;
      } 
      uint256 duration = block.timestamp.sub(lastUpdated[_owner]);
      return Math.min(maxBonus, lastBonus[_owner].add(bonusRate.mul(duration)));
  }

  function getCurrentAvgBonus(address _owner, uint256 _duration)
    public view returns(uint256) {
      if(staked[_owner] == 0) {
        return 0;
      } 
      uint256 avgBonus;
      if(lastBonus[_owner] < maxBonus) {
        uint256 durationTillMax = maxBonus.sub(lastBonus[_owner]).div(bonusRate);
        if(_duration > durationTillMax) {
          uint256 avgWeightedBonusTillMax = lastBonus[_owner].add(maxBonus).div(2).mul(durationTillMax);
          uint256 weightedMaxBonus = maxBonus.mul(_duration.sub(durationTillMax));

          avgBonus = avgWeightedBonusTillMax.add(weightedMaxBonus).div(_duration);
        } else {
          avgBonus = lastBonus[_owner].add(bonusRate.mul(_duration)).add(lastBonus[_owner]).div(2);
        }
      } else {
        avgBonus = maxBonus;
      }
      return avgBonus;
  }

  function setReward(uint256 _rewardRate, uint256 _minRewardStake)
    external onlyOwner {
      rewardRate = _rewardRate;
      minRewardStake = _minRewardStake;

      emit RewardSet(rewardRate, minRewardStake);
  }

  function setBonus(uint256 _maxBonus, uint256 _bonusDuration)
    external onlyOwner {
      maxBonus = _maxBonus.mul(bonusDecimals);
      bonusDuration = _bonusDuration;
      bonusRate = maxBonus.div(_bonusDuration);

      emit BonusesSet(_maxBonus, _bonusDuration);
  }
  
  function stake(uint256 _amount)
    external nonReentrant balanceUpdate(_msgSender()) {
      require(_amount > 0, "TwtStakingPool: _amount is 0");

      twtToken.safeTransferFrom(_msgSender(), address(this), _amount);

      totalSupply = totalSupply.add(_amount);      
      uint256 currentStake = staked[_msgSender()];
      staked[_msgSender()] = staked[_msgSender()].add(_amount);
      lastBonus[_msgSender()] = lastBonus[_msgSender()].mul(currentStake).div(staked[_msgSender()]);

      emit TokensStaked(_msgSender(), _amount, block.timestamp);
  }
  
  function withdraw(uint256 _amount)
    external nonReentrant balanceUpdate(_msgSender()) {
      staked[_msgSender()] = staked[_msgSender()].sub(_amount);
      totalSupply = totalSupply.sub(_amount);

      twtToken.safeTransfer(_msgSender(), _amount);
      
      emit TokensWithdrawn(_msgSender(), _amount, block.timestamp);
  }

  function withdrawEth(uint256 _amount)
    external onlyOwner {
      require(_amount <= address(this).balance, "TwtStakingPool: not enough balance");
      (bool success, ) = _msgSender().call{ value: _amount }("");
      require(success, "TwtStakingPool: transfer failed");
      emit EthWithdrawn(_amount);
  }

  function calculateBonus(address _owner, uint256 _amount, uint256 _duration)
    private view returns(uint256) {
      uint256 avgBonus = getCurrentAvgBonus(_owner, _duration);
      return _amount.add(_amount.mul(avgBonus).div(bonusDecimals).div(100));
  }
}

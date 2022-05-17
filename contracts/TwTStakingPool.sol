// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

//IN PROGRESS
contract TwtStakingPool is AccessControl, ReentrancyGuard {
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  
  uint256 public constant BONUS_DECIMALS = 10000;
  uint256 public constant REWARD_DECIMALS = 100000;

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  struct PoolInfo {
    IERC20 token;
    uint256 rewardRate;
    uint256 minRewardStake;
    uint256 maxBonus;
    uint256 bonusDuration;
    uint256 bonusRate;
    bool active;
  }

  struct UserInfo {
    uint256 staked;
    uint256 lastBonus;
    uint256 lastUpdated;
  }

  uint256 priceByEth;

  PoolInfo[] public poolInfo;
  mapping (uint256 => mapping (address => UserInfo)) public userInfo;
  mapping (address => uint256) public balances;

  event EthWithdrawn(uint256 amount);
  event PointsMinted(address owner, uint256 amount);
  event PointsBurned(address owner, uint256 amount);
  event PointsBought(address owner, uint256 amount);
  event PointsPriceSet(uint256 price);

  event PoolInfoSet(uint256 poolId, uint256 rewardRate, uint256 minRewardStake, uint256 maxBonus, uint256 bonusDuration, uint256 bonusRate);
  event PoolAdded(uint256 poolId, uint256 rewardRate, uint256 minRewardStake, uint256 maxBonus, uint256 bonusDuration, uint256 bonusRate);

  event TokensStaked(uint256 poolId, address payer, uint256 amount, uint256 timestamp);
  event TokensWithdrawn(uint256 poolId, address owner, uint256 amount, uint256 timestamp);

  constructor(uint256 _priceByEth) {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    priceByEth = _priceByEth;
  }

  modifier onlyOwner() {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TwtStakingPool: caller is not an owner");
    _;
  }

  modifier onlyBurner() {
    require(hasRole(BURNER_ROLE, _msgSender()), "TwtStakingPool: caller is not a burner");
    _;
  }

  modifier onlyMinter() {
    require(hasRole(MINTER_ROLE, _msgSender()), "TwtStakingPool: caller is not a minter");
    _;
  }
  
  modifier balanceUpdate(address _owner, uint256 _pId) {
    uint256 duration = block.timestamp.sub(userInfo[_pId][_owner].lastUpdated);
    uint256 reward = calculateReward(_owner, _pId, userInfo[_pId][_owner].staked, duration);
    
    balances[_owner] = balances[_owner].add(reward);
    userInfo[_pId][_owner].lastUpdated = block.timestamp;
    userInfo[_pId][_owner].lastBonus = Math.min(
      poolInfo[_pId].maxBonus, 
      userInfo[_pId][_owner].lastBonus.add(poolInfo[_pId].bonusRate.mul(duration))
    );
    _;
  }

  function poolLength() public view returns(uint256) {
    return poolInfo.length;
  }

  function getRewardByDuration(address _owner, uint256 _pId, uint256 _amount, uint256 _duration) public view returns(uint256) {
    return calculateReward(_owner, _pId, _amount, _duration);
  }

  function getStaked(address _owner, uint256 _pId) public view returns(uint256) {
    return userInfo[_pId][_owner].staked;
  }
  
  function balanceOf(address _owner, uint256 _pId) public view returns(uint256) {
    uint256 totalNewReward;

    for (uint256 i; i < poolLength(); i++) {
      totalNewReward = totalNewReward.add(calculateReward(_owner, _pId, userInfo[_pId][_owner].staked, block.timestamp.sub(userInfo[_pId][_owner].lastUpdated)));
    }   

    return balances[_owner].add(totalNewReward);
  }

  function getCurrentBonus(address _owner, uint256 _pId) public view returns(uint256) {
    if(userInfo[_pId][_owner].staked == 0) {
      return 0;
    } 
 
    uint256 duration = block.timestamp.sub(userInfo[_pId][_owner].lastUpdated);
    return Math.min(poolInfo[_pId].maxBonus, userInfo[_pId][_owner].lastBonus.add(poolInfo[_pId].bonusRate.mul(duration)));
  }

  function getCurrentAvgBonus(address _owner, uint256 _pId, uint256 _duration) public view returns(uint256) {
    if (userInfo[_pId][_owner].staked == 0) {
      return 0;
    } 

    uint256 avgBonus;
    if(userInfo[_pId][_owner].lastBonus < poolInfo[_pId].maxBonus) {
      uint256 durationTillMax = poolInfo[_pId].maxBonus.sub(userInfo[_pId][_owner].lastBonus).div(poolInfo[_pId].bonusRate);
      if(_duration > durationTillMax) {
        uint256 avgWeightedBonusTillMax = userInfo[_pId][_owner].lastBonus.add(poolInfo[_pId].maxBonus).div(2).mul(durationTillMax);
        uint256 weightedMaxBonus = poolInfo[_pId].maxBonus.mul(_duration.sub(durationTillMax));

        avgBonus = avgWeightedBonusTillMax.add(weightedMaxBonus).div(_duration);
      } else {
        avgBonus = userInfo[_pId][_owner].lastBonus.add(poolInfo[_pId].bonusRate.mul(_duration)).add(userInfo[_pId][_owner].lastBonus).div(2);
      }
    } else {
      avgBonus = poolInfo[_pId].maxBonus;
    }

    return avgBonus;
  }

  function setPoolInfo(uint256 _pId, uint256 _rewardRate, uint256 _minRewardStake, uint256 _maxBonus, uint256 _bonusDuration, uint256 _bonusRate)  external onlyOwner {
    poolInfo[_pId].rewardRate = _rewardRate;
    poolInfo[_pId].minRewardStake = _minRewardStake;
    poolInfo[_pId].maxBonus = _maxBonus;
    poolInfo[_pId].bonusDuration = _bonusDuration;
    poolInfo[_pId].bonusRate = _bonusRate;

    emit PoolInfoSet(_pId, _rewardRate, _minRewardStake, _maxBonus, _bonusDuration, _bonusRate);
  }

  function addPool(address _token, uint256 _rewardRate, uint256 _minRewardStake, uint256 _maxBonus, uint256 _bonusDuration, uint256 _bonusRate) external onlyOwner {
    poolInfo.push(PoolInfo({
      token: IERC20(_token),
      rewardRate: _rewardRate,
      minRewardStake: _minRewardStake,
      maxBonus: _maxBonus,
      bonusDuration: _bonusDuration,
      bonusRate: _bonusRate,
      active: true
    }));

    emit PoolAdded(poolLength(), _rewardRate, _minRewardStake, _maxBonus, _bonusDuration, _bonusRate);
  }

  function setPoolState(uint256 _pId, bool _state) external onlyOwner {
    poolInfo[_pId].active = _state;
  }

  function setPrice(uint256 _priceByEth) external onlyOwner {
    priceByEth = _priceByEth;
    emit PointsPriceSet(_priceByEth);
  }
  
  function stake(uint256 _amount, uint256 _pId) external nonReentrant balanceUpdate(_msgSender(), _pId) {
    require(_amount > 0, "TwtStakingPool: _amount is 0");
    require(poolInfo[_pId].active, "TwtStakingPool: pool inactive");

    poolInfo[_pId].token.safeTransferFrom(_msgSender(), address(this), _amount);

    uint256 currentStake = userInfo[_pId][_msgSender()].staked;
    userInfo[_pId][_msgSender()].staked = userInfo[_pId][_msgSender()].staked.add(_amount);
    userInfo[_pId][_msgSender()].lastBonus = userInfo[_pId][_msgSender()].lastBonus.mul(currentStake).div(userInfo[_pId][_msgSender()].staked);

    emit TokensStaked(_pId, _msgSender(), _amount, block.timestamp);
  }
  
  function withdraw(uint256 _amount, uint256 _pId) external nonReentrant balanceUpdate(_msgSender(), _pId) {
    userInfo[_pId][_msgSender()].staked = userInfo[_pId][_msgSender()].staked.sub(_amount);
    poolInfo[_pId].token.safeTransfer(_msgSender(), _amount);

    emit TokensWithdrawn(_pId, _msgSender(), _amount, block.timestamp);
  }

  function withdrawEth(uint256 _amount) external onlyOwner {
    require(_amount <= address(this).balance, "TwtStakingPool: not enough balance");
    (bool success, ) = _msgSender().call{ value: _amount }("");
    require(success, "TwtStakingPool: transfer failed");

    emit EthWithdrawn(_amount);
  }

  function calculateReward(address _owner, uint256 _pId, uint256 _amount, uint256 _duration) private view returns(uint256) {
    uint256 reward = _duration.mul(poolInfo[_pId].rewardRate)
      .mul(_amount)
      .div(REWARD_DECIMALS)
      .div(poolInfo[_pId].minRewardStake);

    return calculateBonus(_owner, _pId, reward, _duration);
  }

  function calculateBonus(address _owner, uint256 _pId, uint256 _amount, uint256 _duration) private view returns(uint256) {
    uint256 avgBonus = getCurrentAvgBonus(_owner, _pId, _duration);
    return _amount.add(_amount.mul(avgBonus).div(BONUS_DECIMALS).div(100));
  }

  function buyPoints() external payable nonReentrant {
    uint256 amount = msg.value * priceByEth;
    balances[_msgSender()] = balances[_msgSender()].add(amount);

    emit PointsBought(_msgSender(), amount);
  }

  function mint(address _owner, uint256 _amount) external nonReentrant onlyMinter {
    balances[_owner] = balances[_owner].add(_amount);
    emit PointsMinted(_owner, _amount);
  }

  function burn(address _owner, uint256 _amount) external nonReentrant onlyBurner {
    balances[_owner] = balances[_owner].sub(_amount);
    emit PointsBurned(_owner, _amount);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MultiBridgePool is AccessControl, ReentrancyGuard {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  event Deposited(address indexed token, address outToken, address indexed spender, address recipient, uint256 amount, uint256 requestId);
  event Withdrawn(address indexed token, address indexed owner, uint256 amount, uint256 requestId);
  event EthWithdrawn(uint256 amount);

  event FeeSet(address token, uint256 fee, uint256 percentFee, uint256 percentFeeDecimals, uint256 tokenToEth);
  event TokenConfigSet(address token, address outAddress, uint256 maxTxsCount, uint256 txsCount);
  event Initialized(address token, address outAddress, uint256 maxTxsCount, uint256 fee, uint256 percentFee, uint256 percentFeeDecimals, uint256 tokenToEth);
  event Removed(address token);

  event AutoWithdrawFeeSet(bool autoWithdraw);
  event TreasuryAddressSet(address treasuryAddress);

  struct TokenInfo {
    address outAddress;
    uint256 maxTxsCount;
    uint256 txsCount;
    bool exists;
    uint256 fee;
    uint256 percentFee;
    uint256 percentFeeDecimals;
    uint256 tokenToEth;
  }

  mapping(address => TokenInfo) private tokens;

  uint256 private requestId;

  bool    private autoWithdrawFee;
  address private treasuryAddress;

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(MINTER_ROLE, _msgSender());

    treasuryAddress = _msgSender();
  }

  modifier onlyMinter() {
    require(hasRole(MINTER_ROLE, _msgSender()), "MultiBridgePool: caller is not a minter");
    _;
  }

  modifier onlyOwner() {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "MultiBridgePool: caller is not an owner");
    _;
  }

  function getFee(address _token, uint256 _amount) 
    public view returns (uint256) {
      TokenInfo memory info = tokens[_token];
      if (!info.exists) {
        return 0;
      }

      if (info.percentFee == 0) {
        return info.fee;
      }

      uint256 _tokenInEth = _amount.div(info.tokenToEth);
    
      uint256 decimals = IERC20Metadata(_token).decimals();

      return info.fee.add(_tokenInEth.mul(1e18).mul(info.percentFee).div(10 ** info.percentFeeDecimals).div(10 ** decimals)); 
  }

  function getTokenInfo(address _token)
    public view returns (TokenInfo memory) {
      return tokens[_token];
  }

  function setFee(address _token, uint256 _fee, uint256 _percentFee, uint256 _percentFeeDecimals, uint256 _tokenToEth)
    external onlyOwner {
      require(tokens[_token].exists, "MultiBridgePool: token unsupported");

      tokens[_token].fee = _fee;
      tokens[_token].percentFee = _percentFee;
      tokens[_token].percentFeeDecimals = _percentFeeDecimals;
      tokens[_token].tokenToEth = _tokenToEth;

      emit FeeSet(_token, _fee, _percentFee, _percentFeeDecimals, _tokenToEth);
  }

  function setTokenConfig(address _token, address _outAddress, uint256 _maxTxsCount, uint256 _txsCount) 
    external onlyOwner {
      require(tokens[_token].exists, "MultiBridgePool: token unsupported");

      tokens[_token].outAddress = _outAddress;
      tokens[_token].maxTxsCount = _maxTxsCount;
      tokens[_token].txsCount = _txsCount;

      emit TokenConfigSet(_token, _outAddress, _maxTxsCount, _txsCount);      
  }

  function init(address _token, address _outAddress, uint256 _maxTxsCount, uint256 _fee, uint256 _percentFee, uint256 _percentFeeDecimals, uint256 _tokenToEth) 
    external onlyOwner {
      require(!tokens[_token].exists, "MultiBridgePool: token already exists");
      
      tokens[_token] = TokenInfo({
         outAddress: _outAddress,
         maxTxsCount: _maxTxsCount,
         txsCount: 0,
         exists: true,
         fee: _fee,
         percentFee: _percentFee,
         percentFeeDecimals: _percentFeeDecimals,
         tokenToEth: _tokenToEth
      });

      emit Initialized({
        token: _token,
        outAddress: _outAddress,
        maxTxsCount: _maxTxsCount,
        fee: _fee,
        percentFee: _percentFee,
        percentFeeDecimals: _percentFeeDecimals,
        tokenToEth: _tokenToEth
      });
  }

  function remove(address _token) 
    external onlyOwner {
      delete tokens[_token];
      emit Removed(_token);
  }

  function setAutoWithdrawFee(bool _autoWithdrawFee)
    external onlyOwner {
      autoWithdrawFee = _autoWithdrawFee;
      emit AutoWithdrawFeeSet(autoWithdrawFee);
  }

  function setTreasuryAddress(address _treasuryAddress)
    external onlyOwner {
      treasuryAddress = _treasuryAddress;
      emit TreasuryAddressSet(_treasuryAddress);
  }

  function deposit(address _token, address _recipient, uint256 _amount) 
    external payable nonReentrant {
      require(tokens[_token].exists, "MultiBridgePool: token unsupported");
      require(tokens[_token].maxTxsCount > tokens[_token].txsCount, "MultiBridgePool: max transactions count reached");

      uint256 depositFee = getFee(_token, _amount);
      require(msg.value >= depositFee, "MultiBridgePool: not enough eth");

      uint256 balanceBefore = IERC20(_token).balanceOf(address(this));
      IERC20(_token).safeTransferFrom(_msgSender(), address(this), _amount);
      uint256 balanceAfter = IERC20(_token).balanceOf(address(this));

      uint256 refund = msg.value.sub(depositFee);
      if(refund > 0) {
        (bool refundSuccess, ) = _msgSender().call{ value: refund }("");
        require(refundSuccess, "MultiBridgePool: refund transfer failed");
      }

      if (autoWithdrawFee) {
        (bool withdrawSuccess, ) = treasuryAddress.call{ value: depositFee }("");
        require(withdrawSuccess, "MultiBridgePool: withdraw transfer failed");
      }

      requestId++;
      tokens[_token].txsCount++;
      emit Deposited(_token, tokens[_token].outAddress, _msgSender(), _recipient, balanceAfter - balanceBefore, requestId);
  }

  function withdraw(address[] calldata _tokens, address[] calldata _owners, uint256[] calldata _amounts, uint256[] calldata _requestsIds) 
    external onlyMinter {
      require(_owners.length == _amounts.length && _owners.length == _requestsIds.length && _owners.length == _tokens.length, "MultiBridgePool: Arrays length not equal");

      for (uint256 i; i < _owners.length; i++) {
        IERC20(_tokens[i]).safeTransfer(_owners[i], _amounts[i]);
        emit Withdrawn(_tokens[i], _owners[i], _amounts[i], _requestsIds[i]);
      }
  }

  function withdrawEth(uint256 _amount)
    external onlyOwner {
      require(_amount <= address(this).balance, "MultiBridgePool: not enough balance");
      
      (bool success, ) = _msgSender().call{ value: _amount }("");
      require(success, "MultiBridgePool: transfer failed");

      emit EthWithdrawn(_amount);
  }
}

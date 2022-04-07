//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import './interface/IUniswapV2Pair.sol';
import './interface/IUniswapV2Factory.sol';
import './interface/IUniswapV2Router.sol';

contract HotDogeStaking is OwnableUpgradeable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
    uint256 pendingRewards;
    uint256 lastAction;
  }

  struct PoolInfo {
    IERC20 stakeToken;
    IERC20 rewardToken;
    uint256 rewardPerBlock;
    uint256 lockupDuration;
    uint256 lastRewardBlock;
    uint256 accTokenPerShare;
    uint256 depositedAmount;
    bool lpPool;
  }

  PoolInfo[] public poolInfo;
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;

  IUniswapV2Router02 public uniswapV2Router;
  uint256 private constant CONST_MULTIPLIER = 1e20;

  uint256 public fee;
  uint256 public devFee;
  address public teamAddress;
  address public devAddress;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 amount
  );
  event Claim(address indexed user, uint256 indexed pid, uint256 amount);

  function initialize() public initializer {
    uniswapV2Router = IUniswapV2Router02(
      0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D // eth router
      // 0x10ED43C718714eb63d5aA57B78B54704E256024E  // mainnet router
      // 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3 // testnet router
    );
    teamAddress = address(0xaBf84100cD55a933a2Cb269F15A557CE74C6fd8a);
    devAddress = address(0xaBf84100cD55a933a2Cb269F15A557CE74C6fd8a);
    fee = 20;
    devFee = 20;

    __Ownable_init();
  }

  //to recieve ETH from uniswapV2Router when swaping
  receive() external payable {}

  function setUniswapV2Router(address _addr) external onlyOwner {
    uniswapV2Router = IUniswapV2Router02(_addr);
  }

  function setFee(uint256 _fee) external onlyOwner {
    fee = _fee;
  }

  function setDevFee(uint256 _fee) external onlyOwner {
    devFee = _fee;
  }

  function setTeamAddress(address _addr) external onlyOwner {
    require(_addr != address(0), 'Address cannot be zero');
    teamAddress = _addr;
  }

  function setDevAddress(address _addr) external onlyOwner {
    require(_addr != address(0), 'Address cannot be zero');
    devAddress = _addr;
  }

  function addPool(
    IERC20 _stakeToken,
    IERC20 _rewardToken,
    uint256 _rewardPerBlock,
    uint256 _lockupDuration,
    bool _lpPool
  ) external onlyOwner {
    poolInfo.push(
      PoolInfo({
        stakeToken: _stakeToken,
        rewardToken: _rewardToken,
        rewardPerBlock: _rewardPerBlock,
        lockupDuration: _lockupDuration,
        lastRewardBlock: block.number,
        accTokenPerShare: 0,
        depositedAmount: 0,
        lpPool: _lpPool
      })
    );
  }

  function updatePool(
    uint256 pid,
    IERC20 _rewardToken,
    uint256 _lockupDuration,
    bool _lpPool
  ) external onlyOwner {
    require(pid < poolInfo.length, 'Invalid pool id');

    PoolInfo storage pool = poolInfo[pid];
    pool.rewardToken = _rewardToken;
    pool.lockupDuration = _lockupDuration;
    pool.lpPool = _lpPool;
  }

  function pendingRewards(uint256 pid, address _user)
    external
    view
    returns (uint256)
  {
    PoolInfo storage pool = poolInfo[pid];
    UserInfo storage user = userInfo[pid][_user];
    uint256 accTokenPerShare = pool.accTokenPerShare;
    uint256 depositedAmount = pool.depositedAmount;
    if (block.number > pool.lastRewardBlock && depositedAmount != 0) {
      uint256 multiplier = block.number.sub(pool.lastRewardBlock);
      uint256 tokenReward = multiplier.mul(pool.rewardPerBlock);
      accTokenPerShare = accTokenPerShare.add(
        tokenReward.mul(CONST_MULTIPLIER).div(depositedAmount)
      );
    }
    return
      user
        .amount
        .mul(accTokenPerShare)
        .div(CONST_MULTIPLIER)
        .sub(user.rewardDebt)
        .add(user.pendingRewards);
  }

  function _updatePool(uint256 pid) internal {
    require(pid < poolInfo.length, 'Invalid pool id');

    PoolInfo storage pool = poolInfo[pid];
    uint256 depositedAmount = pool.depositedAmount;
    if (pool.depositedAmount == 0) {
      pool.lastRewardBlock = block.number;
      return;
    }

    uint256 multiplier = block.number.sub(pool.lastRewardBlock);
    uint256 tokenReward = multiplier.mul(pool.rewardPerBlock);
    pool.accTokenPerShare = pool.accTokenPerShare.add(
      tokenReward.mul(CONST_MULTIPLIER).div(depositedAmount)
    );
    pool.lastRewardBlock = block.number;
  }

  function deposit(uint256 pid, uint256 amount) external {
    PoolInfo storage pool = poolInfo[pid];
    UserInfo storage user = userInfo[pid][msg.sender];

    _updatePool(pid);

    if (user.amount > 0) {
      uint256 pending = user
        .amount
        .mul(pool.accTokenPerShare)
        .div(CONST_MULTIPLIER)
        .sub(user.rewardDebt);

      if (pending > 0) {
        user.pendingRewards = user.pendingRewards.add(pending);
      }
    }

    if (amount > 0) {
      pool.stakeToken.safeTransferFrom(
        address(msg.sender),
        address(this),
        amount
      );

      if (!pool.lpPool) {
        uint256 feeAmount = amount.mul(fee).div(1000);
        amount = amount.sub(feeAmount);
        swapAndDistribute(pool.stakeToken, feeAmount);
      }

      user.amount = user.amount.add(amount);
      pool.depositedAmount = pool.depositedAmount.add(amount);
    }

    user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(
      CONST_MULTIPLIER
    );

    user.lastAction = block.timestamp;

    emit Deposit(msg.sender, pid, amount);
  }

  function withdraw(uint256 pid, uint256 amount) public {
    PoolInfo storage pool = poolInfo[pid];
    UserInfo storage user = userInfo[pid][msg.sender];

    require(user.amount >= amount, 'Withdrawing more than you have!');
    require(
      user.lastAction.add(pool.lockupDuration) <= block.timestamp,
      'You cannot withdraw yet!'
    );

    _updatePool(pid);

    uint256 pending = user
      .amount
      .mul(pool.accTokenPerShare)
      .div(CONST_MULTIPLIER)
      .sub(user.rewardDebt);

    if (pending > 0) {
      user.pendingRewards = user.pendingRewards.add(pending);
    }

    if (amount > 0) {
      pool.stakeToken.safeTransfer(address(msg.sender), amount);
      user.amount = user.amount.sub(amount);
      pool.depositedAmount = pool.depositedAmount.sub(amount);
    }

    user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(
      CONST_MULTIPLIER
    );

    user.lastAction = block.timestamp;

    emit Withdraw(msg.sender, pid, amount);
  }

  function withdrawAll(uint256 pid) external {
    UserInfo storage user = userInfo[pid][msg.sender];

    withdraw(pid, user.amount);
  }

  function emergencyWithdraw(uint256 pid) external {
    PoolInfo storage pool = poolInfo[pid];
    UserInfo storage user = userInfo[pid][msg.sender];

    _updatePool(pid);

    if (user.amount > 0) {
      pool.stakeToken.safeTransfer(address(msg.sender), user.amount);
      pool.depositedAmount = pool.depositedAmount.sub(user.amount);
    }

    emit EmergencyWithdraw(msg.sender, pid, user.amount);

    user.pendingRewards = 0;
    user.rewardDebt = 0;
    user.amount = 0;
    user.lastAction = block.timestamp;
  }

  function claim(uint256 pid) external {
    PoolInfo storage pool = poolInfo[pid];
    UserInfo storage user = userInfo[pid][msg.sender];

    _updatePool(pid);

    uint256 pending = user
      .amount
      .mul(pool.accTokenPerShare)
      .div(CONST_MULTIPLIER)
      .sub(user.rewardDebt);

    if (pending > 0 || user.pendingRewards > 0) {
      user.pendingRewards = user.pendingRewards.add(pending);
      uint256 claimedAmount = safeRewardTransfer(
        pool.rewardToken,
        msg.sender,
        user.pendingRewards
      );
      user.pendingRewards = user.pendingRewards.sub(claimedAmount);
      emit Claim(msg.sender, pid, claimedAmount);
    }

    user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(
      CONST_MULTIPLIER
    );
  }

  function swapAndDistribute(IERC20 token, uint256 tokenAmount) private {
    swapTokensForEth(token, tokenAmount);

    uint256 devAmount = address(this).balance.mul(devFee).div(100);
    uint256 teamAmount = address(this).balance.sub(devAmount);

    payable(teamAddress).call{value: teamAmount}('');
    payable(devAddress).call{value: devAmount}('');
  }

  function swapTokensForEth(IERC20 token, uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(token);
    path[1] = uniswapV2Router.WETH();

    token.approve(address(uniswapV2Router), tokenAmount);

    // make the swap
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this),
      block.timestamp
    );
  }

  function safeRewardTransfer(
    IERC20 token,
    address to,
    uint256 amount
  ) internal returns (uint256) {
    uint256 _rewardBalance = token.balanceOf(address(this));
    if (amount > _rewardBalance) amount = _rewardBalance;
    token.safeTransfer(to, amount);
    return amount;
  }

  function ownerWithdraw(IERC20 token, uint256 _amount) external onlyOwner {
    uint256 _bal = token.balanceOf(address(this));
    if (_amount > _bal) _amount = _bal;

    token.safeTransfer(_msgSender(), _amount);
  }

  function getPoolCount() external view returns (uint256) {
    return poolInfo.length;
  }
}

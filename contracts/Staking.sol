// stake: Lock tokens into our smart contracts
// withdraw/unstake: unlock tokens and pull out of the contract
// claimReward: users get their reward tokens
//      What's a good reward mechanism?
//      What's some good reward math?

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error Staking__TransferFailed();
error Staking__NeedsMoreThanZero();

contract Staking is ReentrancyGuard{
  IERC20 public s_stakingToken;
  IERC20 public s_rewardToken;

  // someone address -> to how much they staked
  mapping(address => uint256) public s_balances;

  // a mapping of how much each address has been paid
  mapping(address => uint256) public s_userRewardPerTokenPaid;

  // a mappiing of how much rewards each address has 
  mapping(address => uint256) public s_rewards;

  uint256 public constant REWARD_RATE = 100;
  uint256 public s_totalSupply;
  uint256 public s_rewardPerTokenStored;
  uint256 public s_lastUpdateTime;

  modifier updateReward(address account) {
    // how much reward per token?
    // last timestamp
    // between timeperiods of 12(noon) to 1, user earns X tokens
    s_rewardPerTokenStored = rewardPerToken();
    s_lastUpdateTime = block.timestamp;
    s_rewards[account] = earned(account);
    s_userRewardPerTokenPaid[account] = s_rewardPerTokenStored;
    _;
  }

  modifier moreThanZero(uint256 amount) {
    if (amount <= 0) {
      revert Staking__NeedsMoreThanZero();
    }
    _;
  }

  // setting the address of the stakingToken
  // to one specific ERC20 token
  constructor(address stakingToken, address rewardToken) {
    s_stakingToken = IERC20(stakingToken);
    s_rewardToken = IERC20(rewardToken);
  }

  function earned(address account) public view returns (uint256) {
    uint256 currentBalance = s_balances[account];
    // how much they have been paid already
    uint256 amountPaid = s_userRewardPerTokenPaid[account];
    uint256 currentRewardPerToken = rewardPerToken();
    uint256 pastRewards = s_rewards[account];
    uint256 _earned = (((currentBalance * (currentRewardPerToken - amountPaid)) /
      1e18) + pastRewards);
    return _earned;
  }

  // Based on how long it's been during this most recent snapshot
  function rewardPerToken() public view returns (uint256) {
    if (s_totalSupply == 0) {
      return s_rewardPerTokenStored;
    }
    return
      s_rewardPerTokenStored +
      (((block.timestamp - s_lastUpdateTime) * REWARD_RATE * 1e18) /
        s_totalSupply);
  }

  // do we allow any tokens?
  //   -Chainlink stuff to convert prices between different tokens
  // or just a specific token?
  // this example only allows one speicific ERC20 token
  function stake(uint256 amount) external updateReward(msg.sender) nonReentrant moreThanZero(amount) {
    // keep track of how much this user has staked
    // keep track of how much token we have total
    // transfer the tokens to this contract
    s_balances[msg.sender] = s_balances[msg.sender] + amount;
    s_totalSupply = s_totalSupply + amount;
    // emit event here
    bool success = s_stakingToken.transferFrom(
      msg.sender,
      address(this),
      amount
    );
    // require(success, "Failure"); // Not Gas Efficient
    if (!success) {
      revert Staking__TransferFailed();
    }
  }

  function withdraw(uint256 amount) external updateReward(msg.sender) nonReentrant moreThanZero(amount) {
    s_balances[msg.sender] = s_balances[msg.sender] - amount;
    s_totalSupply = s_totalSupply - amount;
    bool success = s_stakingToken.transfer(msg.sender, amount);
    // using transfer in this case is the same as the follwing since msg.sender in this case is the staking contract
    // bool success = s_stakingToken.transferFrom(address(this), msg.sender, amount);
    if (!success) {
      revert Staking__TransferFailed();
    }
  }

  function claimReward() external updateReward(msg.sender) nonReentrant {
    uint256 reward = s_rewards[msg.sender];
    bool success = s_rewardToken.transfer(msg.sender, reward);
    if(!success) {
      revert Staking__TransferFailed();
    }
    // How much reward do they get?
    // The contract is going to emit X tokens per second
    // And disperse them to all token stakers
    //
    // 100 tokens / second
    // staked:  50 staked tokens, 20 staked tokens, 30 staked tokens
    // rewards: 50 reward tokens, 20 reward tokens, 30 reward tokens
    //
    // The more people stake, the more the reward gets divided
    // staked: 100, 50, 20. 30 (total = 200)
    // reward:  50, 25, 10, 15
    //
    // why not 1 to 1? - this will bankrupt your protocol
    //
    //Example 1:
    // 5 seconds, 1 person had 100 tokens staked = reward 500 tokens
    // 6 seconds, 2 person have 100 tokens staked each:
    //     Person 1: 550  (500 from previous 5 seconds; he got 50 tokens in this second)
    //     Person 2: 50
    // ok between seconds 1 to 5, person got 500 tokens
    // ok at second 6 on, person 1 gets 50 tokens now
    //
    // Example 2:
    // Total Tokens staked = 100 tokens
    // 1 token / staked token
    //
    // Time = 0
    // Person A: 80 staked
    // Person B: 20 staked
    //
    // Time = 1
    // Person A: 80 staked, Earned: 80, Withdrawn: 0
    // Person B: 20 staked, Earned: 20, Withdrawn: 0
    //
    // Time = 2
    // Person A: 80 staked, Earned: 160, Withdrawn: 0
    // Person B: 20 staked, Earned: 40, Withdrawn: 0
    //
    // Time = 3
    // Person A: 80 staked, Earned: 240, Withdrawn: 0
    // Person B: 20 staked, Earned: 60, Withdrawn: 0
    //
    // New Person enters!
    // Stakes 100
    // Total Tokens staked = 200
    // 0.5 token / staked token
    //
    // Time = 4
    // Person A: 80 staked, Earned: 240 + [(80 / 200) * 100] = 240 + 40 = 280, Withdrawn: 0
    // Person B: 20 staked, Earned: 60 + [(20 / 200) * 100] = 60 + 10 = 70, Withdrawn: 0
    // Person C: 100 staked, Earned: [(100 / 200) * 100] = 50, Withdrawn: 0
    //
    // Person A withdrew and claimed rewards on everything
    //
    // Time = 5
    // Person A: 0 staked, Earned: 0, Withdrawn: 280
    // Person B: 20 staked, Earned: 70 + [(20 / 120) * 100] = 70 + 16.66 = 80.66, Withdrawn: 0
    // Person C: 100 staked, Earned: 50 + [(100 / 120) * 100] = 50 + 83.33 = 133.33, Withdrawn: 0
  }
}

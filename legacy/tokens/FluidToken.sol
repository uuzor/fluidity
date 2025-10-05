// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FluidToken
 * @dev Governance token for the Fluid Protocol
 */
contract FluidToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, Ownable, Pausable {
    // Token distribution
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18; // 1 billion tokens
    uint256 public constant TEAM_ALLOCATION = 200_000_000e18; // 20%
    uint256 public constant COMMUNITY_ALLOCATION = 400_000_000e18; // 40%
    uint256 public constant LIQUIDITY_MINING = 300_000_000e18; // 30%
    uint256 public constant TREASURY_ALLOCATION = 100_000_000e18; // 10%

    // Vesting
    mapping(address => uint256) public vestedAmount;
    mapping(address => uint256) public claimedAmount;
    mapping(address => uint256) public vestingStart;
    mapping(address => uint256) public vestingDuration;

    // Staking
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakingRewards;
    mapping(address => uint256) public lastStakeTime;
    
    uint256 public totalStaked;
    uint256 public rewardRate = 100; // 1% per year base rate
    uint256 public constant REWARD_PRECISION = 10000;

    // Events
    event TokensVested(address indexed beneficiary, uint256 amount, uint256 duration);
    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event TokensStaked(address indexed user, uint256 amount);
    event TokensUnstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    constructor() 
        ERC20("Fluid Protocol Token", "FLUID") 
        ERC20Permit("Fluid Protocol Token")
        Ownable(msg.sender)
    {
        // Mint total supply to contract for controlled distribution
        _mint(address(this), TOTAL_SUPPLY);
    }

    /**
     * @dev Distribute tokens to different allocations
     */
    function distributeTokens(
        address team,
        address community,
        address liquidityMining,
        address treasury
    ) external onlyOwner {
        require(team != address(0) && community != address(0) && liquidityMining != address(0) && treasury != address(0), "Invalid addresses");
        
        // Transfer allocations
        _transfer(address(this), team, TEAM_ALLOCATION);
        _transfer(address(this), community, COMMUNITY_ALLOCATION);
        _transfer(address(this), liquidityMining, LIQUIDITY_MINING);
        _transfer(address(this), treasury, TREASURY_ALLOCATION);
    }

    /**
     * @dev Set up vesting schedule for an address
     */
    function setupVesting(address beneficiary, uint256 amount, uint256 duration) external onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");
        require(balanceOf(address(this)) >= amount, "Insufficient contract balance");

        vestedAmount[beneficiary] = amount;
        vestingStart[beneficiary] = block.timestamp;
        vestingDuration[beneficiary] = duration;

        emit TokensVested(beneficiary, amount, duration);
    }

    /**
     * @dev Claim vested tokens
     */
    function claimVestedTokens() external {
        uint256 claimable = getClaimableAmount(msg.sender);
        require(claimable > 0, "No tokens to claim");

        claimedAmount[msg.sender] += claimable;
        _transfer(address(this), msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }

    /**
     * @dev Get claimable vested amount for an address
     */
    function getClaimableAmount(address beneficiary) public view returns (uint256) {
        if (vestedAmount[beneficiary] == 0) return 0;
        
        uint256 elapsed = block.timestamp - vestingStart[beneficiary];
        uint256 duration = vestingDuration[beneficiary];
        
        if (elapsed >= duration) {
            return vestedAmount[beneficiary] - claimedAmount[beneficiary];
        }
        
        uint256 vested = (vestedAmount[beneficiary] * elapsed) / duration;
        return vested - claimedAmount[beneficiary];
    }

    /**
     * @dev Stake tokens for governance and rewards
     */
    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Update rewards before staking
        _updateRewards(msg.sender);

        // Transfer tokens to contract
        _transfer(msg.sender, address(this), amount);
        
        // Update staking state
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
        lastStakeTime[msg.sender] = block.timestamp;

        emit TokensStaked(msg.sender, amount);
    }

    /**
     * @dev Unstake tokens
     */
    function unstake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked balance");

        // Update rewards before unstaking
        _updateRewards(msg.sender);

        // Update staking state
        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);

        emit TokensUnstaked(msg.sender, amount);
    }

    /**
     * @dev Claim staking rewards
     */
    function claimRewards() external {
        _updateRewards(msg.sender);
        
        uint256 rewards = stakingRewards[msg.sender];
        require(rewards > 0, "No rewards to claim");

        stakingRewards[msg.sender] = 0;
        
        // Mint rewards (inflation mechanism)
        _mint(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @dev Update staking rewards for a user
     */
    function _updateRewards(address user) internal {
        if (stakedBalance[user] == 0) return;

        uint256 timeStaked = block.timestamp - lastStakeTime[user];
        uint256 rewards = (stakedBalance[user] * rewardRate * timeStaked) / (365 days * REWARD_PRECISION);
        
        stakingRewards[user] += rewards;
        lastStakeTime[user] = block.timestamp;
    }

    /**
     * @dev Get pending rewards for a user
     */
    function getPendingRewards(address user) external view returns (uint256) {
        if (stakedBalance[user] == 0) return stakingRewards[user];

        uint256 timeStaked = block.timestamp - lastStakeTime[user];
        uint256 pendingRewards = (stakedBalance[user] * rewardRate * timeStaked) / (365 days * REWARD_PRECISION);
        
        return stakingRewards[user] + pendingRewards;
    }

    /**
     * @dev Set reward rate (only owner)
     */
    function setRewardRate(uint256 newRate) external onlyOwner {
        require(newRate <= 1000, "Rate too high"); // Max 10%
        
        uint256 oldRate = rewardRate;
        rewardRate = newRate;
        
        emit RewardRateUpdated(oldRate, newRate);
    }

    /**
     * @dev Override transfer to update rewards
     */
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        _updateRewards(msg.sender);
        _updateRewards(to);
        return super.transfer(to, amount);
    }

    /**
     * @dev Override transferFrom to update rewards
     */
    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        _updateRewards(from);
        _updateRewards(to);
        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Get voting power (staked balance)
     */
    function getVotes(address account) public view override returns (uint256) {
        return stakedBalance[account];
    }

    /**
     * @dev Get past voting power
     */
    function getPastVotes(address account, uint256 timepoint) public view override returns (uint256) {
        // Simplified implementation - in production, you'd want to track historical balances
        return stakedBalance[account];
    }

    // Required overrides for multiple inheritance
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
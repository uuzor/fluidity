// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../security/SecurityBase.sol";
import "../../interfaces/IYieldStrategy.sol";

contract LiquidStakingStrategy is SecurityBase, IYieldStrategy {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable stakingToken;
    address public immutable override asset;
    address public override vault;
    uint256 public totalStaked;
    uint256 public rewardRate = 5e16; // 5% APY
    bool public initialized;
    
    mapping(address => uint256) public userStakes;
    mapping(address => uint256) public lastRewardTime;
    
    event RewardsClaimed(address indexed user, uint256 amount);
    
    constructor(address _accessControl, address _stakingToken) SecurityBase(_accessControl) {
        stakingToken = IERC20(_stakingToken);
        asset = _stakingToken;
    }
    
    function initialize(address _asset, address _vault) external override onlyValidRole(accessControl.ADMIN_ROLE()) {
        require(!initialized, "Already initialized");
        require(_asset == asset, "Asset mismatch");
        vault = _vault;
        initialized = true;
    }
    
    function getYield(address _asset) external view returns (uint256) {
        if (_asset != address(stakingToken) || userStakes[msg.sender] == 0) return 0;
        
        uint256 timeStaked = block.timestamp - lastRewardTime[msg.sender];
        return (userStakes[msg.sender] * rewardRate * timeStaked) / (365 days * 1e18);
    }
    
    function claimRewards() external nonReentrant returns (uint256) {
        uint256 rewards = this.getYield(address(stakingToken));
        if (rewards > 0) {
            lastRewardTime[msg.sender] = block.timestamp;
            // In real implementation, mint reward tokens
            emit RewardsClaimed(msg.sender, rewards);
        }
        return rewards;
    }
    
    function getTotalValue() external view returns (uint256) {
        return totalStaked;
    }
    
    function getUserBalance(address user) external view returns (uint256) {
        return userStakes[user];
    }
    
    function setRewardRate(uint256 _rewardRate) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        require(_rewardRate <= 20e16, "Rate too high"); // Max 20%
        rewardRate = _rewardRate;
    }
    
    // Interface implementations
    function deposit(uint256 amount) external override nonReentrant {
        require(amount > 0, "Invalid amount");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender] += amount;
        totalStaked += amount;
        lastRewardTime[msg.sender] = block.timestamp;
        emit Deposited(amount);
    }
    
    function withdraw(uint256 amount) external override nonReentrant returns (uint256) {
        require(userStakes[msg.sender] >= amount, "Insufficient stake");
        userStakes[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(amount);
        return amount;
    }
    
    function withdrawAll() external override nonReentrant returns (uint256) {
        uint256 amount = userStakes[msg.sender];
        if (amount > 0) {
            userStakes[msg.sender] = 0;
            totalStaked -= amount;
            stakingToken.safeTransfer(msg.sender, amount);
            emit Withdrawn(amount);
        }
        return amount;
    }
    
    function harvest() external override nonReentrant returns (uint256 profit) {
        profit = this.getPendingRewards();
        if (profit > 0) {
            lastRewardTime[msg.sender] = block.timestamp;
            emit Harvested(profit);
        }
        return profit;
    }
    
    function rebalance() external override onlyValidRole(accessControl.ADMIN_ROLE()) {
        emit Rebalanced();
    }
    
    function emergencyWithdraw() external override onlyValidRole(accessControl.EMERGENCY_ROLE()) returns (uint256) {
        uint256 amount = userStakes[msg.sender];
        if (amount > 0) {
            userStakes[msg.sender] = 0;
            totalStaked -= amount;
            stakingToken.safeTransfer(msg.sender, amount);
            emit EmergencyWithdraw(amount);
        }
        return amount;
    }
    
    function balanceOf() external view override returns (uint256) {
        return userStakes[msg.sender];
    }
    
    function getAllocatedAmount() external view override returns (uint256) {
        return totalStaked;
    }
    
    function getPendingRewards() external view override returns (uint256) {
        if (userStakes[msg.sender] == 0) return 0;
        uint256 timeStaked = block.timestamp - lastRewardTime[msg.sender];
        return (userStakes[msg.sender] * rewardRate * timeStaked) / (365 days * 1e18);
    }
    
    function getAPY() external view override returns (uint256) {
        return rewardRate;
    }
    
    function isHealthy() external view override returns (bool) {
        return true; // Simplified
    }
    
    function strategyName() external pure override returns (string memory) {
        return "Liquid Staking Strategy";
    }
    
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
    
    function registerForSonicFeeM(uint256 projectId) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        (bool success,) = address(0xDC2B0D2Dd2b7759D97D50db4eabDC36973110830).call(
            abi.encodeWithSignature("selfRegister(uint256)", projectId)
        );
        require(success, "FeeM registration failed");
    }
}
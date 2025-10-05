// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IYieldStrategy
 * @dev Interface for yield generation strategies
 */
interface IYieldStrategy {
    // Events
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 profit);
    event Rebalanced();
    event EmergencyWithdraw(uint256 amount);

    // Core Functions
    function initialize(address asset, address vault) external;
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256);
    function withdrawAll() external returns (uint256);
    function harvest() external returns (uint256 profit);
    function rebalance() external;
    function emergencyWithdraw() external returns (uint256);

    // View Functions
    function balanceOf() external view returns (uint256);
    function getAllocatedAmount() external view returns (uint256);
    function getPendingRewards() external view returns (uint256);
    function getAPY() external view returns (uint256);
    function isHealthy() external view returns (bool);
    
    // Strategy Info
    function asset() external view returns (address);
    function vault() external view returns (address);
    function strategyName() external view returns (string memory);
    function version() external view returns (string memory);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVaultManager
 * @dev Interface for managing yield strategies and vaults
 */
interface IVaultManager {
    struct VaultInfo {
        address strategy;
        address asset;
        uint256 totalDeposits;
        uint256 totalShares;
        uint256 performanceFee;
        uint256 managementFee;
        uint256 lastHarvest;
        bool isActive;
        bool emergencyExit;
    }

    struct StrategyParams {
        uint256 maxDeposit;
        uint256 minDeposit;
        uint256 withdrawalFee;
        uint256 performanceFee;
        uint256 managementFee;
        uint256 harvestDelay;
    }

    // Events
    event VaultCreated(address indexed vault, address indexed strategy, address indexed asset);
    event Deposited(address indexed user, address indexed vault, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, address indexed vault, uint256 shares, uint256 amount);
    event Harvested(address indexed vault, uint256 profit, uint256 fees);
    event StrategyUpdated(address indexed vault, address oldStrategy, address newStrategy);
    event EmergencyExit(address indexed vault, uint256 amount);

    // Vault Management
    function createVault(address strategy, address asset, StrategyParams calldata params) external returns (address vault);
    function updateStrategy(address vault, address newStrategy) external;
    function setVaultParams(address vault, StrategyParams calldata params) external;
    function pauseVault(address vault) external;
    function unpauseVault(address vault) external;

    // User Operations
    function deposit(address vault, uint256 amount) external returns (uint256 shares);
    function withdraw(address vault, uint256 shares) external returns (uint256 amount);
    function withdrawAll(address vault) external returns (uint256 amount);

    // Strategy Operations
    function harvest(address vault) external returns (uint256 profit);
    function rebalance(address vault) external;
    function emergencyWithdraw(address vault) external;

    // View Functions
    function getVaultInfo(address vault) external view returns (VaultInfo memory);
    function getUserShares(address user, address vault) external view returns (uint256);
    function getUserBalance(address user, address vault) external view returns (uint256);
    function getVaultTVL(address vault) external view returns (uint256);
    function getVaultAPY(address vault) external view returns (uint256);
    function getAllVaults() external view returns (address[] memory);
    function getVaultsByAsset(address asset) external view returns (address[] memory);

    // Strategy Integration
    function getStrategyBalance(address vault) external view returns (uint256);
    function getStrategyAllocatedAmount(address vault) external view returns (uint256);
    function canHarvest(address vault) external view returns (bool);
}
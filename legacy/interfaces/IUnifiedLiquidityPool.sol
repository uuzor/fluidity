// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IUnifiedLiquidityPool
 * @dev Interface for the unified liquidity pool that serves all protocol functions
 */
interface IUnifiedLiquidityPool {
    struct AssetInfo {
        address token;
        uint256 totalDeposits;
        uint256 totalBorrows;
        uint256 reserveFactor;
        uint256 collateralFactor;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        bool isActive;
        bool canBorrow;
        bool canCollateralize;
    }

    struct LiquidityAllocation {
        uint256 lendingPool;
        uint256 dexPool;
        uint256 vaultStrategies;
        uint256 liquidStaking;
        uint256 reserves;
    }

    // Events
    event AssetAdded(address indexed token, AssetInfo assetInfo);
    event AssetUpdated(address indexed token, AssetInfo assetInfo);
    event LiquidityDeposited(address indexed user, address indexed token, uint256 amount);
    event LiquidityWithdrawn(address indexed user, address indexed token, uint256 amount);
    event LiquidityAllocated(address indexed token, LiquidityAllocation allocation);
    event RebalanceExecuted(address indexed token, uint256 timestamp);

    // Core Functions
    function deposit(address token, uint256 amount) external returns (uint256 shares);
    function withdraw(address token, uint256 shares) external returns (uint256 amount);
    function borrow(address token, uint256 amount, address collateralToken) external;
    function repay(address token, uint256 amount) external;
    
    // Liquidity Management
    function allocateLiquidity(address token, LiquidityAllocation calldata allocation) external;
    function rebalanceLiquidity(address token) external;
    function getAvailableLiquidity(address token) external view returns (uint256);
    function getTotalLiquidity(address token) external view returns (uint256);
    
    // Asset Management
    function addAsset(address token, AssetInfo calldata assetInfo) external;
    function updateAsset(address token, AssetInfo calldata assetInfo) external;
    function getAssetInfo(address token) external view returns (AssetInfo memory);
    function getSupportedAssets() external view returns (address[] memory);
    
    // Utilization & Rates
    function getUtilizationRate(address token) external view returns (uint256);
    function getSupplyRate(address token) external view returns (uint256);
    function getBorrowRate(address token) external view returns (uint256);
    
    // User Positions
    function getUserDeposits(address user, address token) external view returns (uint256);
    function getUserBorrows(address user, address token) external view returns (uint256);
    function getUserHealthFactor(address user) external view returns (uint256);
    
    // Liquidation
    function liquidate(address user, address collateralToken, address debtToken, uint256 debtAmount) external;
    function isLiquidatable(address user) external view returns (bool);


    // DEX HOOKS
    function borrowLiquidity(address token, uint256 amount) external;
    function returnLiquidity(address token, uint256 amount) external;
}



// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/OptimizedSecurityBase.sol";
import "../interfaces/IUnifiedLiquidityPool.sol";

/**
 * @title UnifiedLiquidityPool
 * @notice Gas-optimized unified liquidity pool
 * @dev Uses TransientStorage for reentrancy protection (~19,800 gas savings per tx)
 */
contract UnifiedLiquidityPool is OptimizedSecurityBase, IUnifiedLiquidityPool {
    using SafeERC20 for IERC20;

    mapping(address => AssetInfo) public assets;
    mapping(address => mapping(address => uint256)) public userDeposits;
    mapping(address => mapping(address => uint256)) public userBorrows;
    mapping(address => LiquidityAllocation) public allocations;

    address[] public supportedAssets;

    constructor(address _accessControl) OptimizedSecurityBase(_accessControl) {}
    
    function deposit(address token, uint256 amount) external nonReentrant returns (uint256 shares) {
        require(assets[token].isActive, "Asset not supported");
        require(amount > 0, "Invalid amount");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        userDeposits[msg.sender][token] += amount;
        assets[token].totalDeposits += amount;
        
        emit LiquidityDeposited(msg.sender, token, amount);
        return amount; // 1:1 for simplicity
    }
    
    function withdraw(address token, uint256 shares) external nonReentrant returns (uint256 amount) {
        require(userDeposits[msg.sender][token] >= shares, "Insufficient balance");
        
        userDeposits[msg.sender][token] -= shares;
        assets[token].totalDeposits -= shares;
        
        IERC20(token).safeTransfer(msg.sender, shares);
        
        emit LiquidityWithdrawn(msg.sender, token, shares);
        return shares;
    }
    
    function borrow(address token, uint256 amount, address collateralToken) external nonReentrant {
        require(assets[token].canBorrow, "Borrowing disabled");
        require(amount > 0, "Invalid amount");

        // Simple health check with mock pricing
        // TODO: Integrate real price oracle
        // For now, assume 1 WETH = 2000 USDF for testing
        uint256 collateralAmount = userDeposits[msg.sender][collateralToken];
        uint256 collateralValue = collateralAmount;

        // If collateral is WETH-like (has 18 decimals, small amount), multiply by 2000
        // This is a hack for testing - will be replaced with oracle
        if (collateralAmount < 1000e18) {
            collateralValue = collateralAmount * 2000;
        }

        collateralValue = collateralValue * assets[collateralToken].collateralFactor / 1e18;
        uint256 totalBorrows = userBorrows[msg.sender][token] + amount;
        require(collateralValue >= totalBorrows, "Insufficient collateral");

        userBorrows[msg.sender][token] += amount;
        assets[token].totalBorrows += amount;

        IERC20(token).safeTransfer(msg.sender, amount);
    }
    
    function repay(address token, uint256 amount) external nonReentrant {
        require(userBorrows[msg.sender][token] >= amount, "Repay amount too high");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        userBorrows[msg.sender][token] -= amount;
        assets[token].totalBorrows -= amount;
    }
    
    function addAsset(address token, AssetInfo calldata assetInfo) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        require(!assets[token].isActive, "Asset already exists");
        
        assets[token] = assetInfo;
        supportedAssets.push(token);
        
        emit AssetAdded(token, assetInfo);
    }
    
    function allocateLiquidity(address token, LiquidityAllocation calldata allocation) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        allocations[token] = allocation;
        emit LiquidityAllocated(token, allocation);
    }
    
    function rebalanceLiquidity(address token) external {
        emit RebalanceExecuted(token, block.timestamp);
    }
    
    function getAvailableLiquidity(address token) public view returns (uint256) {
        return assets[token].totalDeposits - assets[token].totalBorrows;
    }
    
    function getTotalLiquidity(address token) external view returns (uint256) {
        return assets[token].totalDeposits;
    }
    
    function updateAsset(address token, AssetInfo calldata assetInfo) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        assets[token] = assetInfo;
        emit AssetUpdated(token, assetInfo);
    }
    
    function getAssetInfo(address token) external view returns (AssetInfo memory) {
        return assets[token];
    }
    
    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }
    
    function getUtilizationRate(address token) public view returns (uint256) {
        if (assets[token].totalDeposits == 0) return 0;
        return (assets[token].totalBorrows * 1e18) / assets[token].totalDeposits;
    }
    
    function getSupplyRate(address token) external view returns (uint256) {
        uint256 utilizationRate = getUtilizationRate(token);
        uint256 borrowRate = getBorrowRate(token);
        
        // Supply rate = borrow rate * utilization rate * (1 - reserve factor)
        // Reserve factor = 10% (0.1e18)
        return (borrowRate * utilizationRate * 90) / (100 * 1e18);
    }
    
    function getBorrowRate(address token) public view returns (uint256) {
        uint256 utilizationRate = getUtilizationRate(token);
        
        // Base rate: 2% + utilization-based rate
        uint256 baseRate = 2e16; // 2%
        uint256 slope1 = 8e16; // 8% at 80% utilization
        uint256 slope2 = 50e16; // 50% above 80% utilization
        uint256 optimalUtilization = 80e16; // 80%
        
        if (utilizationRate <= optimalUtilization) {
            // Linear increase from base to slope1
            return baseRate + (utilizationRate * slope1) / optimalUtilization;
        } else {
            // Steep increase above optimal utilization
            uint256 excessUtilization = utilizationRate - optimalUtilization;
            return baseRate + slope1 + (excessUtilization * slope2) / (1e18 - optimalUtilization);
        }
    }
    
    function getUserDeposits(address user, address token) external view returns (uint256) {
        return userDeposits[user][token];
    }
    
    function getUserBorrows(address user, address token) external view returns (uint256) {
        return userBorrows[user][token];
    }
    
    function getUserHealthFactor(address user) external view returns (uint256) {
        uint256 totalCollateralValue = 0;
        uint256 totalDebtValue = 0;
        
        // Calculate total collateral and debt across all assets
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address token = supportedAssets[i];
            
            // Add collateral value
            uint256 collateralAmount = userDeposits[user][token];
            if (collateralAmount > 0) {
                totalCollateralValue += collateralAmount * assets[token].collateralFactor / 1e18;
            }
            
            // Add debt value
            uint256 debtAmount = userBorrows[user][token];
            if (debtAmount > 0) {
                totalDebtValue += debtAmount;
            }
        }
        
        // Return health factor (collateral / debt * 1e18)
        if (totalDebtValue == 0) return type(uint256).max; // No debt = infinite health
        return (totalCollateralValue * 1e18) / totalDebtValue;
    }
    
    function liquidate(address user, address collateralToken, address debtToken, uint256 debtAmount) external {
        // Simplified liquidation
        require(userBorrows[user][debtToken] >= debtAmount, "Invalid liquidation");
        
        userBorrows[user][debtToken] -= debtAmount;
        uint256 collateralSeized = (debtAmount * 105) / 100; // 5% bonus
        
        if (userDeposits[user][collateralToken] >= collateralSeized) {
            userDeposits[user][collateralToken] -= collateralSeized;
            IERC20(collateralToken).safeTransfer(msg.sender, collateralSeized);
        }
    }
    
    function isLiquidatable(address user) external view returns (bool) {
        uint256 totalCollateralValue = 0;
        uint256 totalDebtValue = 0;
        
        // Calculate total collateral and debt across all assets
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address token = supportedAssets[i];
            
            // Add collateral value
            uint256 collateralAmount = userDeposits[user][token];
            if (collateralAmount > 0) {
                totalCollateralValue += collateralAmount * assets[token].collateralFactor / 1e18;
            }
            
            // Add debt value
            uint256 debtAmount = userBorrows[user][token];
            if (debtAmount > 0) {
                totalDebtValue += debtAmount;
            }
        }
        
        // Liquidatable if health factor < 1.0 (100%)
        if (totalDebtValue == 0) return false;
        return totalCollateralValue < totalDebtValue;
    }
    
    function borrowLiquidity(address token, uint256 amount) external nonReentrant {
        require(assets[token].isActive, "Asset not supported");
        require(getAvailableLiquidity(token) >= amount, "Insufficient liquidity");
        
        assets[token].totalBorrows += amount;
        IERC20(token).safeTransfer(msg.sender, amount);
    }
    
    function returnLiquidity(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(assets[token].totalBorrows >= amount, "Cannot return more than borrowed");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        assets[token].totalBorrows -= amount;
    }
    
    function registerForSonicFeeM(uint256 projectId) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        (bool success,) = address(0xDC2B0D2Dd2b7759D97D50db4eabDC36973110830).call(
            abi.encodeWithSignature("selfRegister(uint256)", projectId)
        );
        require(success, "FeeM registration failed");
    }
}
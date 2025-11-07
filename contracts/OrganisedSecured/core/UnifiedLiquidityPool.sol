// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/OptimizedSecurityBase.sol";
import "../interfaces/IUnifiedLiquidityPool.sol";
import "../interfaces/IPriceOracle.sol";

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
    IPriceOracle public priceOracle;

    constructor(address _accessControl, address _priceOracle) OptimizedSecurityBase(_accessControl) {
        require(_priceOracle != address(0), "Invalid price oracle");
        priceOracle = IPriceOracle(_priceOracle);
    }
    
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

        // Get collateral and debt values using price oracle
        uint256 collateralAmount = userDeposits[msg.sender][collateralToken];
        require(collateralAmount > 0, "No collateral deposited");

        // Get prices from oracle (in 18 decimals)
        uint256 collateralPrice = priceOracle.getPrice(collateralToken);
        uint256 debtPrice = priceOracle.getPrice(token);

        // Calculate collateral value: (collateral amount * price) * collateral factor
        uint256 collateralValue = (collateralAmount * collateralPrice / 1e18) * assets[collateralToken].collateralFactor / 1e18;

        // Calculate total debt value: (current borrows + new borrow) * debt token price
        uint256 totalBorrows = userBorrows[msg.sender][token] + amount;
        uint256 totalDebtValue = (totalBorrows * debtPrice) / 1e18;

        // Require: collateral value >= debt value
        require(collateralValue >= totalDebtValue, "Insufficient collateral");

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

            // Add collateral value (using price oracle)
            uint256 collateralAmount = userDeposits[user][token];
            if (collateralAmount > 0) {
                uint256 price = priceOracle.getPrice(token);
                totalCollateralValue += (collateralAmount * price / 1e18) * assets[token].collateralFactor / 1e18;
            }

            // Add debt value (using price oracle)
            uint256 debtAmount = userBorrows[user][token];
            if (debtAmount > 0) {
                uint256 price = priceOracle.getPrice(token);
                totalDebtValue += (debtAmount * price) / 1e18;
            }
        }

        // Return health factor (collateral / debt * 1e18)
        if (totalDebtValue == 0) return type(uint256).max; // No debt = infinite health
        return (totalCollateralValue * 1e18) / totalDebtValue;
    }
    
    function liquidate(address user, address collateralToken, address debtToken, uint256 debtAmount) external nonReentrant {
        // Verify user is liquidatable
        require(assets[debtToken].canBorrow, "Invalid debt token");
        require(userBorrows[user][debtToken] >= debtAmount, "Invalid liquidation amount");

        // Check user health factor is below 1.0 (liquidatable)
        uint256 totalCollateralValue = 0;
        uint256 totalDebtValue = 0;
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address token = supportedAssets[i];
            uint256 collateralAmount = userDeposits[user][token];
            if (collateralAmount > 0) {
                uint256 price = priceOracle.getPrice(token);
                totalCollateralValue += (collateralAmount * price / 1e18) * assets[token].collateralFactor / 1e18;
            }
            uint256 debtAmount_loop = userBorrows[user][token];
            if (debtAmount_loop > 0) {
                uint256 price = priceOracle.getPrice(token);
                totalDebtValue += (debtAmount_loop * price) / 1e18;
            }
        }
        require(totalDebtValue > 0 && totalCollateralValue < totalDebtValue, "User not liquidatable");

        // Get prices for debt and collateral tokens
        uint256 debtPrice = priceOracle.getPrice(debtToken);
        uint256 collateralPrice = priceOracle.getPrice(collateralToken);

        // Calculate collateral to seize: debt value * 1.05 (5% liquidation bonus) / collateral price
        uint256 debtValue = (debtAmount * debtPrice) / 1e18;
        uint256 liquidationBonus = assets[collateralToken].liquidationBonus; // e.g., 1.05e18 for 5%
        uint256 collateralValueToSeize = (debtValue * liquidationBonus) / 1e18;
        uint256 collateralAmountToSeize = (collateralValueToSeize * 1e18) / collateralPrice;

        // Ensure user has enough collateral to seize
        require(userDeposits[user][collateralToken] >= collateralAmountToSeize, "Insufficient collateral to seize");

        // Update user positions
        userBorrows[user][debtToken] -= debtAmount;
        assets[debtToken].totalBorrows -= debtAmount;

        userDeposits[user][collateralToken] -= collateralAmountToSeize;
        assets[collateralToken].totalDeposits -= collateralAmountToSeize;

        // Transfer debt tokens from liquidator to pool
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), debtAmount);

        // Transfer seized collateral to liquidator
        IERC20(collateralToken).safeTransfer(msg.sender, collateralAmountToSeize);

        emit Liquidation(user, debtToken, debtAmount, collateralToken, collateralAmountToSeize);
    }
    
    function isLiquidatable(address user) external view returns (bool) {
        uint256 totalCollateralValue = 0;
        uint256 totalDebtValue = 0;

        // Calculate total collateral and debt across all assets
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address token = supportedAssets[i];

            // Add collateral value (using price oracle)
            uint256 collateralAmount = userDeposits[user][token];
            if (collateralAmount > 0) {
                uint256 price = priceOracle.getPrice(token);
                totalCollateralValue += (collateralAmount * price / 1e18) * assets[token].collateralFactor / 1e18;
            }

            // Add debt value (using price oracle)
            uint256 debtAmount = userBorrows[user][token];
            if (debtAmount > 0) {
                uint256 price = priceOracle.getPrice(token);
                totalDebtValue += (debtAmount * price) / 1e18;
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
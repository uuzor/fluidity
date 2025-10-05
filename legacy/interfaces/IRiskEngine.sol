// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRiskEngine
 * @dev Interface for the risk management engine
 */
interface IRiskEngine {
    struct RiskParameters {
        uint256 baseLTV;           // Base loan-to-value ratio
        uint256 liquidationLTV;    // LTV at which liquidation occurs
        uint256 liquidationThreshold; // Liquidation threshold
        uint256 liquidationBonus;  // Bonus for liquidators
        uint256 volatilityFactor;  // Asset volatility multiplier
        uint256 correlationFactor; // Correlation with other assets
        uint256 liquidityFactor;   // Liquidity depth factor
    }

    struct UserRiskProfile {
        uint256 totalCollateralValue;
        uint256 totalDebtValue;
        uint256 healthFactor;
        uint256 liquidationThreshold;
        bool isLiquidatable;
        address[] collateralAssets;
        address[] debtAssets;
    }

    struct MarketRisk {
        uint256 utilizationRate;
        uint256 volatilityIndex;
        uint256 liquidityDepth;
        uint256 concentrationRisk;
        uint256 correlationRisk;
    }

    // Events
    event RiskParametersUpdated(address indexed asset, RiskParameters params);
    event HealthFactorUpdated(address indexed user, uint256 healthFactor);
    event LiquidationTriggered(address indexed user, address indexed liquidator, uint256 healthFactor);
    event RiskThresholdBreached(address indexed asset, uint256 riskLevel);

    // Risk Parameter Management
    function setRiskParameters(address asset, RiskParameters calldata params) external;
    function getRiskParameters(address asset) external view returns (RiskParameters memory);
    function updateVolatilityFactor(address asset, uint256 volatilityFactor) external;
    function updateCorrelationMatrix(address[] calldata assets, uint256[][] calldata correlations) external;

    // User Risk Assessment
    function calculateHealthFactor(address user) external view returns (uint256);
    function getUserRiskProfile(address user) external view returns (UserRiskProfile memory);
    function isUserLiquidatable(address user) external view returns (bool);
    function getMaxBorrowAmount(address user, address asset) external view returns (uint256);
    function getMaxWithdrawAmount(address user, address asset) external view returns (uint256);

    // Market Risk Assessment
    function getMarketRisk(address asset) external view returns (MarketRisk memory);
    function getSystemRisk() external view returns (uint256);
    function isMarketStressed(address asset) external view returns (bool);
    function getRecommendedLTV(address asset) external view returns (uint256);

    // Dynamic Risk Adjustments
    function adjustRiskParameters(address asset) external;
    function emergencyPause(address asset) external;
    function emergencyUnpause(address asset) external;
    function setGlobalRiskMultiplier(uint256 multiplier) external;

    // Liquidation Support
    function calculateLiquidationAmount(address user, address collateralAsset, address debtAsset) external view returns (uint256);
    function getLiquidationBonus(address collateralAsset) external view returns (uint256);
    function canLiquidate(address user, address liquidator) external view returns (bool);

    // Oracle Integration
    function updateAssetPrice(address asset, uint256 price) external;
    function getAssetPrice(address asset) external view returns (uint256);
    function getPriceWithConfidence(address asset) external view returns (uint256 price, uint256 confidence);

    // Risk Monitoring
    function monitorUserPositions(address[] calldata users) external;
    function getHighRiskUsers() external view returns (address[] memory);
    function getRiskScore(address user) external view returns (uint256);
}
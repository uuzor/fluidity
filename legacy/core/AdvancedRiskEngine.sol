// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Math.sol";

/**
 * @title AdvancedRiskEngine
 * @dev Comprehensive risk management with correlation matrices, dynamic risk weighting, and portfolio analysis
 */
contract AdvancedRiskEngine is Ownable, ReentrancyGuard {
    using Math for uint256;

    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MAX_ASSETS = 50;
    uint256 public constant MAX_CORRELATION = 1e18; // 100%
    uint256 public constant MIN_CORRELATION = 0; // 0%
    uint256 public constant VOLATILITY_WINDOW = 30 days;

    // Asset risk parameters
    struct RiskParameters {
        uint256 baseLTV;              // Base Loan-to-Value ratio
        uint256 liquidationLTV;       // Liquidation threshold
        uint256 liquidationBonus;     // Liquidation bonus percentage
        uint256 volatilityFactor;     // Historical volatility measure
        uint256 liquidityFactor;      // Market liquidity measure
        uint256 concentrationLimit;   // Maximum concentration allowed
        bool isActive;                // Whether asset is active for borrowing
        uint256 riskWeight;           // Risk weight for capital calculations
        uint256 stressTestMultiplier; // Stress test scenario multiplier
    }

    // Correlation matrix entry
    struct CorrelationEntry {
        address asset1;
        address asset2;
        uint256 correlation; // Correlation coefficient (0-1e18)
        uint256 lastUpdated;
    }

    // Portfolio risk metrics
    struct PortfolioRisk {
        uint256 totalRiskWeightedValue;
        uint256 concentrationRisk;
        uint256 correlationRisk;
        uint256 liquidityRisk;
        uint256 overallRiskScore;
    }

    // State variables
    mapping(address => RiskParameters) public riskParameters;
    mapping(bytes32 => uint256) public correlationMatrix; // hash(asset1, asset2) => correlation
    mapping(address => uint256) public assetVolatility; // 30-day rolling volatility
    mapping(address => uint256) public lastVolatilityUpdate;
    mapping(address => uint256[]) public priceHistory; // Price history for volatility calculation
    
    address[] public supportedAssets;
    mapping(address => bool) public isAssetSupported;
    
    // Risk limits
    uint256 public maxPortfolioRisk = 0.8e18; // 80% max risk score
    uint256 public maxSingleAssetConcentration = 0.3e18; // 30% max concentration
    uint256 public maxCorrelatedAssetsConcentration = 0.5e18; // 50% max for correlated assets

    // Events
    event RiskParametersUpdated(address indexed asset, RiskParameters params);
    event CorrelationUpdated(address indexed asset1, address indexed asset2, uint256 correlation);
    event VolatilityUpdated(address indexed asset, uint256 volatility);
    event PortfolioRiskCalculated(address indexed user, PortfolioRisk risk);
    event RiskLimitsUpdated(uint256 maxPortfolioRisk, uint256 maxSingleAsset, uint256 maxCorrelated);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add a new supported asset with risk parameters
     */
    function addAsset(
        address asset,
        uint256 baseLTV,
        uint256 liquidationLTV,
        uint256 liquidationBonus,
        uint256 volatilityFactor,
        uint256 liquidityFactor,
        uint256 concentrationLimit,
        uint256 riskWeight,
        uint256 stressTestMultiplier
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(!isAssetSupported[asset], "Asset already supported");
        require(supportedAssets.length < MAX_ASSETS, "Too many assets");
        require(baseLTV <= liquidationLTV, "Base LTV cannot exceed liquidation LTV");
        require(liquidationLTV <= DECIMAL_PRECISION, "Liquidation LTV cannot exceed 100%");

        riskParameters[asset] = RiskParameters({
            baseLTV: baseLTV,
            liquidationLTV: liquidationLTV,
            liquidationBonus: liquidationBonus,
            volatilityFactor: volatilityFactor,
            liquidityFactor: liquidityFactor,
            concentrationLimit: concentrationLimit,
            isActive: true,
            riskWeight: riskWeight,
            stressTestMultiplier: stressTestMultiplier
        });

        supportedAssets.push(asset);
        isAssetSupported[asset] = true;
        lastVolatilityUpdate[asset] = block.timestamp;

        emit RiskParametersUpdated(asset, riskParameters[asset]);
    }

    /**
     * @dev Update correlation between two assets
     */
    function updateCorrelation(
        address asset1,
        address asset2,
        uint256 correlation
    ) external onlyOwner {
        require(isAssetSupported[asset1] && isAssetSupported[asset2], "Assets not supported");
        require(correlation <= MAX_CORRELATION, "Correlation too high");
        require(asset1 != asset2, "Cannot correlate asset with itself");

        bytes32 key1 = _getCorrelationKey(asset1, asset2);
        bytes32 key2 = _getCorrelationKey(asset2, asset1);
        
        correlationMatrix[key1] = correlation;
        correlationMatrix[key2] = correlation; // Symmetric matrix

        emit CorrelationUpdated(asset1, asset2, correlation);
    }

    /**
     * @dev Update asset price for volatility calculation
     */
    function updateAssetPrice(address asset, uint256 price) external {
        require(isAssetSupported[asset], "Asset not supported");
        require(price > 0, "Invalid price");

        priceHistory[asset].push(price);
        
        // Keep only last 30 data points for volatility calculation
        if (priceHistory[asset].length > 30) {
            // Shift array left by removing first element
            for (uint i = 0; i < priceHistory[asset].length - 1; i++) {
                priceHistory[asset][i] = priceHistory[asset][i + 1];
            }
            priceHistory[asset].pop();
        }

        // Update volatility if enough data points and sufficient time has passed
        if (priceHistory[asset].length >= 7 && 
            block.timestamp >= lastVolatilityUpdate[asset] + 1 days) {
            _updateVolatility(asset);
        }
    }

    /**
     * @dev Calculate portfolio risk for a user's positions
     */
    function calculatePortfolioRisk(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata prices
    ) external view returns (PortfolioRisk memory) {
        require(assets.length == amounts.length && amounts.length == prices.length, "Array length mismatch");
        
        uint256 totalValue = 0;
        uint256 totalRiskWeightedValue = 0;
        
        // Calculate total value and risk-weighted value
        for (uint i = 0; i < assets.length; i++) {
            require(isAssetSupported[assets[i]], "Asset not supported");
            
            uint256 assetValue = amounts[i].mulDiv(prices[i], DECIMAL_PRECISION);
            totalValue += assetValue;
            
            uint256 riskWeight = riskParameters[assets[i]].riskWeight;
            totalRiskWeightedValue += assetValue.mulDiv(riskWeight, DECIMAL_PRECISION);
        }

        // Calculate concentration risk
        uint256 concentrationRisk = _calculateConcentrationRisk(assets, amounts, prices, totalValue);
        
        // Calculate correlation risk
        uint256 correlationRisk = _calculateCorrelationRisk(assets, amounts, prices, totalValue);
        
        // Calculate liquidity risk
        uint256 liquidityRisk = _calculateLiquidityRisk(assets, amounts);
        
        // Calculate overall risk score
        uint256 overallRiskScore = _calculateOverallRiskScore(
            totalRiskWeightedValue,
            totalValue,
            concentrationRisk,
            correlationRisk,
            liquidityRisk
        );

        return PortfolioRisk({
            totalRiskWeightedValue: totalRiskWeightedValue,
            concentrationRisk: concentrationRisk,
            correlationRisk: correlationRisk,
            liquidityRisk: liquidityRisk,
            overallRiskScore: overallRiskScore
        });
    }

    /**
     * @dev Check if a position meets risk requirements
     */
    function validatePosition(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata prices,
        uint256 borrowAmount
    ) external view returns (bool isValid, string memory reason) {
        PortfolioRisk memory risk = this.calculatePortfolioRisk(assets, amounts, prices);
        
        // Check overall portfolio risk
        if (risk.overallRiskScore > maxPortfolioRisk) {
            return (false, "Portfolio risk too high");
        }
        
        // Check single asset concentration
        uint256 totalValue = 0;
        for (uint i = 0; i < amounts.length; i++) {
            totalValue += amounts[i].mulDiv(prices[i], DECIMAL_PRECISION);
        }
        
        for (uint i = 0; i < assets.length; i++) {
            uint256 assetValue = amounts[i].mulDiv(prices[i], DECIMAL_PRECISION);
            uint256 concentration = assetValue.mulDiv(DECIMAL_PRECISION, totalValue);
            
            if (concentration > maxSingleAssetConcentration) {
                return (false, "Single asset concentration too high");
            }
            
            // Check asset-specific concentration limit
            if (concentration > riskParameters[assets[i]].concentrationLimit) {
                return (false, "Asset concentration limit exceeded");
            }
        }
        
        // Check correlated assets concentration
        if (risk.correlationRisk > maxCorrelatedAssetsConcentration) {
            return (false, "Correlated assets concentration too high");
        }
        
        return (true, "");
    }

    /**
     * @dev Get effective LTV for an asset considering current market conditions
     */
    function getEffectiveLTV(address asset, uint256 amount) external view returns (uint256) {
        require(isAssetSupported[asset], "Asset not supported");
        
        RiskParameters memory params = riskParameters[asset];
        uint256 baseLTV = params.baseLTV;
        
        // Adjust LTV based on volatility
        uint256 volatilityAdjustment = assetVolatility[asset].mulDiv(params.volatilityFactor, DECIMAL_PRECISION);
        
        // Adjust LTV based on liquidity
        uint256 liquidityAdjustment = (DECIMAL_PRECISION - params.liquidityFactor).mulDiv(0.1e18, DECIMAL_PRECISION);
        
        // Apply adjustments (reduce LTV for higher risk)
        uint256 effectiveLTV = baseLTV;
        if (volatilityAdjustment + liquidityAdjustment < effectiveLTV) {
            effectiveLTV -= (volatilityAdjustment + liquidityAdjustment);
        } else {
            effectiveLTV = effectiveLTV / 2; // Minimum 50% of base LTV
        }
        
        return effectiveLTV;
    }

    /**
     * @dev Perform stress test on portfolio
     */
    function stressTestPortfolio(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata currentPrices
    ) external view returns (uint256 stressedValue, bool passesStressTest) {
        uint256 totalStressedValue = 0;
        
        for (uint i = 0; i < assets.length; i++) {
            RiskParameters memory params = riskParameters[assets[i]];
            
            // Apply stress test multiplier (typically < 1 for price drops)
            uint256 stressedPrice = currentPrices[i].mulDiv(params.stressTestMultiplier, DECIMAL_PRECISION);
            uint256 stressedAssetValue = amounts[i].mulDiv(stressedPrice, DECIMAL_PRECISION);
            
            totalStressedValue += stressedAssetValue;
        }
        
        // Calculate current value for comparison
        uint256 currentValue = 0;
        for (uint i = 0; i < assets.length; i++) {
            currentValue += amounts[i].mulDiv(currentPrices[i], DECIMAL_PRECISION);
        }
        
        // Portfolio passes stress test if stressed value is > 70% of current value
        bool passes = totalStressedValue >= currentValue.mulDiv(0.7e18, DECIMAL_PRECISION);
        
        return (totalStressedValue, passes);
    }

    // Internal functions

    /**
     * @dev Calculate concentration risk
     */
    function _calculateConcentrationRisk(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata prices,
        uint256 totalValue
    ) internal view returns (uint256) {
        uint256 maxConcentration = 0;
        
        for (uint i = 0; i < assets.length; i++) {
            uint256 assetValue = amounts[i].mulDiv(prices[i], DECIMAL_PRECISION);
            uint256 concentration = assetValue.mulDiv(DECIMAL_PRECISION, totalValue);
            
            if (concentration > maxConcentration) {
                maxConcentration = concentration;
            }
        }
        
        // Risk increases exponentially with concentration
        return maxConcentration.mulDiv(maxConcentration, DECIMAL_PRECISION);
    }

    /**
     * @dev Calculate correlation risk
     */
    function _calculateCorrelationRisk(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata prices,
        uint256 totalValue
    ) internal view returns (uint256) {
        uint256 correlationRisk = 0;
        
        for (uint i = 0; i < assets.length; i++) {
            for (uint j = i + 1; j < assets.length; j++) {
                uint256 correlation = getCorrelation(assets[i], assets[j]);
                
                if (correlation > 0.7e18) { // High correlation threshold
                    uint256 value1 = amounts[i].mulDiv(prices[i], DECIMAL_PRECISION);
                    uint256 value2 = amounts[j].mulDiv(prices[j], DECIMAL_PRECISION);
                    
                    uint256 combinedWeight = (value1 + value2).mulDiv(DECIMAL_PRECISION, totalValue);
                    uint256 correlationContribution = combinedWeight.mulDiv(correlation, DECIMAL_PRECISION);
                    
                    correlationRisk += correlationContribution;
                }
            }
        }
        
        return correlationRisk;
    }

    /**
     * @dev Calculate liquidity risk
     */
    function _calculateLiquidityRisk(
        address[] calldata assets,
        uint256[] calldata amounts
    ) internal view returns (uint256) {
        uint256 liquidityRisk = 0;
        
        for (uint i = 0; i < assets.length; i++) {
            uint256 liquidityFactor = riskParameters[assets[i]].liquidityFactor;
            uint256 illiquidityRisk = DECIMAL_PRECISION - liquidityFactor;
            
            liquidityRisk += illiquidityRisk;
        }
        
        return liquidityRisk / assets.length; // Average liquidity risk
    }

    /**
     * @dev Calculate overall risk score
     */
    function _calculateOverallRiskScore(
        uint256 riskWeightedValue,
        uint256 totalValue,
        uint256 concentrationRisk,
        uint256 correlationRisk,
        uint256 liquidityRisk
    ) internal pure returns (uint256) {
        // Base risk from risk-weighted assets
        uint256 baseRisk = riskWeightedValue.mulDiv(DECIMAL_PRECISION, totalValue);
        
        // Combine all risk factors with weights
        uint256 combinedRisk = baseRisk.mulDiv(0.4e18, DECIMAL_PRECISION) + // 40% weight
                              concentrationRisk.mulDiv(0.3e18, DECIMAL_PRECISION) + // 30% weight
                              correlationRisk.mulDiv(0.2e18, DECIMAL_PRECISION) + // 20% weight
                              liquidityRisk.mulDiv(0.1e18, DECIMAL_PRECISION); // 10% weight
        
        return Math.min(combinedRisk, DECIMAL_PRECISION); // Cap at 100%
    }

    /**
     * @dev Update volatility for an asset
     */
    function _updateVolatility(address asset) internal {
        uint256[] storage prices = priceHistory[asset];
        if (prices.length < 2) return;
        
        // Calculate standard deviation of price returns
        uint256 mean = 0;
        uint256[] memory xreturns = new uint256[](prices.length - 1);
        
        // Calculate xreturns
        for (uint i = 1; i < prices.length; i++) {
            if (prices[i-1] > 0) {
                xreturns[i-1] = prices[i].mulDiv(DECIMAL_PRECISION, prices[i-1]);
                mean += xreturns[i-1];
            }
        }
        
        mean = mean / xreturns.length;
        
        // Calculate variance
        uint256 variance = 0;
        for (uint i = 0; i < xreturns.length; i++) {
            uint256 diff = xreturns[i] > mean ? xreturns[i] - mean : mean - xreturns[i];
            variance += diff.mulDiv(diff, DECIMAL_PRECISION);
        }
        
        variance = variance / xreturns.length;
        
        // Store volatility (simplified square root approximation)
        assetVolatility[asset] = _sqrt(variance);
        lastVolatilityUpdate[asset] = block.timestamp;
        
        emit VolatilityUpdated(asset, assetVolatility[asset]);
    }

    /**
     * @dev Get correlation key for two assets
     */
    function _getCorrelationKey(address asset1, address asset2) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(asset1, asset2));
    }

    /**
     * @dev Simple square root approximation
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // View functions

    /**
     * @dev Get correlation between two assets
     */
    function getCorrelation(address asset1, address asset2) public view returns (uint256) {
        if (asset1 == asset2) return DECIMAL_PRECISION; // Perfect correlation with self
        
        bytes32 key = _getCorrelationKey(asset1, asset2);
        return correlationMatrix[key];
    }

    /**
     * @dev Get risk parameters for an asset
     */
    function getRiskParameters(address asset) external view returns (RiskParameters memory) {
        return riskParameters[asset];
    }

    /**
     * @dev Get current volatility for an asset
     */
    function getAssetVolatility(address asset) external view returns (uint256) {
        return assetVolatility[asset];
    }

    /**
     * @dev Get all supported assets
     */
    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    /**
     * @dev Update risk limits
     */
    function updateRiskLimits(
        uint256 _maxPortfolioRisk,
        uint256 _maxSingleAssetConcentration,
        uint256 _maxCorrelatedAssetsConcentration
    ) external onlyOwner {
        require(_maxPortfolioRisk <= DECIMAL_PRECISION, "Invalid portfolio risk limit");
        require(_maxSingleAssetConcentration <= DECIMAL_PRECISION, "Invalid single asset limit");
        require(_maxCorrelatedAssetsConcentration <= DECIMAL_PRECISION, "Invalid correlated assets limit");
        
        maxPortfolioRisk = _maxPortfolioRisk;
        maxSingleAssetConcentration = _maxSingleAssetConcentration;
        maxCorrelatedAssetsConcentration = _maxCorrelatedAssetsConcentration;
        
        emit RiskLimitsUpdated(_maxPortfolioRisk, _maxSingleAssetConcentration, _maxCorrelatedAssetsConcentration);
    }
}

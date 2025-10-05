// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/Math.sol";

/**
 * @title EnhancedFeeManager
 * @dev Advanced fee management with dynamic base rates, decay functions, and recovery mode adjustments
 */
contract EnhancedFeeManager is Ownable {
    using Math for uint256;

    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant SECONDS_IN_ONE_MINUTE = 60;
    uint256 public constant MINUTE_DECAY_FACTOR = 999037758833783000; // 0.5% per minute decay
    uint256 public constant MAX_BORROWING_FEE = 0.05e18; // 5%
    uint256 public constant MAX_REDEMPTION_FEE = 0.05e18; // 5%
    uint256 public constant BORROWING_FEE_FLOOR = 0.005e18; // 0.5%
    uint256 public constant REDEMPTION_FEE_FLOOR = 0.005e18; // 0.5%
    uint256 public constant BETA = 2; // Exponential factor for fee calculation

    // State variables for each asset
    mapping(address => uint256) public baseRate; // Current base rate per asset
    mapping(address => uint256) public lastFeeOperationTime; // Last fee operation timestamp
    mapping(address => uint256) public totalRedemptions; // Total redemptions for fee calculation
    mapping(address => uint256) public totalBorrowings; // Total borrowings for fee calculation
    
    // Dynamic fee parameters
    mapping(address => FeeParameters) public feeParameters;
    
    // Recovery mode adjustments
    mapping(address => bool) public recoveryMode;
    mapping(address => uint256) public recoveryModeMultiplier; // Fee multiplier in recovery mode

    struct FeeParameters {
        uint256 baseFeeRate;           // Base fee rate (0.5%)
        uint256 maxFeeRate;            // Maximum fee rate (5%)
        uint256 feeMultiplier;         // Multiplier for fee calculation
        uint256 decayFactor;           // Custom decay factor per asset
        uint256 volumeSensitivity;     // How sensitive fees are to volume
        uint256 timeSensitivity;       // How sensitive fees are to time
    }

    // Events
    event BaseRateUpdated(address indexed asset, uint256 newBaseRate);
    event FeeParametersUpdated(address indexed asset, FeeParameters params);
    event RecoveryModeUpdated(address indexed asset, bool enabled, uint256 multiplier);
    event BorrowingFeeCalculated(address indexed asset, uint256 debt, uint256 fee, uint256 baseRate);
    event RedemptionFeeCalculated(address indexed asset, uint256 amount, uint256 fee, uint256 baseRate);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Initialize fee parameters for an asset
     */
    function initializeAsset(
        address asset,
        uint256 baseFeeRate,
        uint256 maxFeeRate,
        uint256 feeMultiplier,
        uint256 decayFactor,
        uint256 volumeSensitivity,
        uint256 timeSensitivity
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        
        feeParameters[asset] = FeeParameters({
            baseFeeRate: baseFeeRate,
            maxFeeRate: maxFeeRate,
            feeMultiplier: feeMultiplier,
            decayFactor: decayFactor,
            volumeSensitivity: volumeSensitivity,
            timeSensitivity: timeSensitivity
        });

        lastFeeOperationTime[asset] = block.timestamp;
        recoveryModeMultiplier[asset] = DECIMAL_PRECISION; // 1x by default

        emit FeeParametersUpdated(asset, feeParameters[asset]);
    }

    /**
     * @dev Calculate borrowing fee with dynamic base rate
     */
    function calculateBorrowingFee(address asset, uint256 debt) external returns (uint256) {
        _decayBaseRate(asset);
        
        uint256 currentBaseRate = baseRate[asset];
        FeeParameters memory params = feeParameters[asset];
        
        // Calculate dynamic fee based on volume and time
        uint256 volumeAdjustment = _calculateVolumeAdjustment(asset, debt, params.volumeSensitivity);
        uint256 timeAdjustment = _calculateTimeAdjustment(asset, params.timeSensitivity);
        
        // Combine base rate with adjustments
        uint256 adjustedRate = currentBaseRate + volumeAdjustment + timeAdjustment;
        
        // Apply recovery mode multiplier if active
        if (recoveryMode[asset]) {
            adjustedRate = adjustedRate.mulDiv(recoveryModeMultiplier[asset], DECIMAL_PRECISION);
        }
        
        // Ensure rate is within bounds
        adjustedRate = Math.max(adjustedRate, params.baseFeeRate);
        adjustedRate = Math.min(adjustedRate, params.maxFeeRate);
        
        uint256 fee = debt.mulDiv(adjustedRate, DECIMAL_PRECISION);
        
        // Update base rate based on borrowing activity
        _updateBaseRateFromBorrowing(asset, debt);
        
        emit BorrowingFeeCalculated(asset, debt, fee, currentBaseRate);
        return fee;
    }

    /**
     * @dev Calculate redemption fee with dynamic base rate
     */
    function calculateRedemptionFee(address asset, uint256 amount) external returns (uint256) {
        _decayBaseRate(asset);
        
        uint256 currentBaseRate = baseRate[asset];
        FeeParameters memory params = feeParameters[asset];
        
        // Calculate dynamic fee based on redemption volume
        uint256 volumeAdjustment = _calculateVolumeAdjustment(asset, amount, params.volumeSensitivity);
        uint256 timeAdjustment = _calculateTimeAdjustment(asset, params.timeSensitivity);
        
        uint256 adjustedRate = currentBaseRate + volumeAdjustment + timeAdjustment;
        
        // Apply recovery mode multiplier if active
        if (recoveryMode[asset]) {
            adjustedRate = adjustedRate.mulDiv(recoveryModeMultiplier[asset], DECIMAL_PRECISION);
        }
        
        // Ensure rate is within bounds
        adjustedRate = Math.max(adjustedRate, params.baseFeeRate);
        adjustedRate = Math.min(adjustedRate, params.maxFeeRate);
        
        uint256 fee = amount.mulDiv(adjustedRate, DECIMAL_PRECISION);
        
        // Update base rate based on redemption activity
        _updateBaseRateFromRedemption(asset, amount);
        
        emit RedemptionFeeCalculated(asset, amount, fee, currentBaseRate);
        return fee;
    }

    /**
     * @dev Update recovery mode status and multiplier
     */
    function setRecoveryMode(address asset, bool enabled, uint256 multiplier) external onlyOwner {
        recoveryMode[asset] = enabled;
        if (enabled) {
            require(multiplier >= DECIMAL_PRECISION, "Multiplier must be >= 1");
            recoveryModeMultiplier[asset] = multiplier;
        } else {
            recoveryModeMultiplier[asset] = DECIMAL_PRECISION;
        }
        
        emit RecoveryModeUpdated(asset, enabled, multiplier);
    }

    /**
     * @dev Get current borrowing rate for an asset
     */
    function getBorrowingRate(address asset) external view returns (uint256) {
        uint256 decayedBaseRate = _getDecayedBaseRate(asset);
        FeeParameters memory params = feeParameters[asset];
        
        uint256 rate = Math.max(decayedBaseRate, params.baseFeeRate);
        
        if (recoveryMode[asset]) {
            rate = rate.mulDiv(recoveryModeMultiplier[asset], DECIMAL_PRECISION);
        }
        
        return Math.min(rate, params.maxFeeRate);
    }

    /**
     * @dev Get current redemption rate for an asset
     */
    function getRedemptionRate(address asset) external view returns (uint256) {
        uint256 decayedBaseRate = _getDecayedBaseRate(asset);
        FeeParameters memory params = feeParameters[asset];
        
        uint256 rate = Math.max(decayedBaseRate, params.baseFeeRate);
        
        if (recoveryMode[asset]) {
            rate = rate.mulDiv(recoveryModeMultiplier[asset], DECIMAL_PRECISION);
        }
        
        return Math.min(rate, params.maxFeeRate);
    }

    // Internal functions

    /**
     * @dev Decay the base rate based on time elapsed
     */
    function _decayBaseRate(address asset) internal {
        uint256 decayedBaseRate = _getDecayedBaseRate(asset);
        baseRate[asset] = decayedBaseRate;
        lastFeeOperationTime[asset] = block.timestamp;
    }

    /**
     * @dev Calculate decayed base rate without updating state
     */
    function _getDecayedBaseRate(address asset) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastFeeOperationTime[asset];
        if (timeElapsed == 0) return baseRate[asset];
        
        uint256 minutesElapsed = timeElapsed / SECONDS_IN_ONE_MINUTE;
        if (minutesElapsed == 0) return baseRate[asset];
        
        FeeParameters memory params = feeParameters[asset];
        uint256 decayFactor = params.decayFactor > 0 ? params.decayFactor : MINUTE_DECAY_FACTOR;
        
        // Calculate decay: baseRate * (decayFactor ^ minutesElapsed)
        uint256 decayMultiplier = _pow(decayFactor, minutesElapsed);
        return baseRate[asset].mulDiv(decayMultiplier, DECIMAL_PRECISION);
    }

    /**
     * @dev Update base rate from borrowing activity
     */
    function _updateBaseRateFromBorrowing(address asset, uint256 debt) internal {
        FeeParameters memory params = feeParameters[asset];
        
        // Increase base rate based on borrowing volume
        uint256 rateIncrease = debt.mulDiv(params.feeMultiplier, totalBorrowings[asset] + debt);
        baseRate[asset] = Math.min(baseRate[asset] + rateIncrease, params.maxFeeRate);
        
        totalBorrowings[asset] += debt;
        lastFeeOperationTime[asset] = block.timestamp;
        
        emit BaseRateUpdated(asset, baseRate[asset]);
    }

    /**
     * @dev Update base rate from redemption activity
     */
    function _updateBaseRateFromRedemption(address asset, uint256 amount) internal {
        FeeParameters memory params = feeParameters[asset];
        
        // Increase base rate based on redemption volume
        uint256 rateIncrease = amount.mulDiv(params.feeMultiplier, totalRedemptions[asset] + amount);
        baseRate[asset] = Math.min(baseRate[asset] + rateIncrease, params.maxFeeRate);
        
        totalRedemptions[asset] += amount;
        lastFeeOperationTime[asset] = block.timestamp;
        
        emit BaseRateUpdated(asset, baseRate[asset]);
    }

    /**
     * @dev Calculate volume-based fee adjustment
     */
    function _calculateVolumeAdjustment(address asset, uint256 amount, uint256 sensitivity) internal view returns (uint256) {
        if (sensitivity == 0) return 0;
        
        uint256 totalVolume = totalBorrowings[asset] + totalRedemptions[asset];
        if (totalVolume == 0) return 0;
        
        // Volume adjustment: higher volume = higher fees
        return amount.mulDiv(sensitivity, totalVolume + amount);
    }

    /**
     * @dev Calculate time-based fee adjustment
     */
    function _calculateTimeAdjustment(address asset, uint256 sensitivity) internal view returns (uint256) {
        if (sensitivity == 0) return 0;
        
        uint256 timeSinceLastOp = block.timestamp - lastFeeOperationTime[asset];
        uint256 hoursSinceLastOp = timeSinceLastOp / 3600; // Convert to hours
        
        // Time adjustment: longer time since last operation = lower fees
        if (hoursSinceLastOp > 24) return 0; // Cap at 24 hours
        
        return sensitivity.mulDiv(24 - hoursSinceLastOp, 24);
    }

    /**
     * @dev Calculate power function for decay calculation
     */
    function _pow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0) return DECIMAL_PRECISION;
        if (exponent == 1) return base;
        
        uint256 result = DECIMAL_PRECISION;
        uint256 currentBase = base;
        
        while (exponent > 0) {
            if (exponent % 2 == 1) {
                result = result.mulDiv(currentBase, DECIMAL_PRECISION);
            }
            currentBase = currentBase.mulDiv(currentBase, DECIMAL_PRECISION);
            exponent /= 2;
        }
        
        return result;
    }

    /**
     * @dev Update fee parameters for an asset
     */
    function updateFeeParameters(
        address asset,
        uint256 baseFeeRate,
        uint256 maxFeeRate,
        uint256 feeMultiplier,
        uint256 decayFactor,
        uint256 volumeSensitivity,
        uint256 timeSensitivity
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(baseFeeRate <= maxFeeRate, "Base rate cannot exceed max rate");
        require(maxFeeRate <= MAX_BORROWING_FEE, "Max rate too high");
        
        feeParameters[asset] = FeeParameters({
            baseFeeRate: baseFeeRate,
            maxFeeRate: maxFeeRate,
            feeMultiplier: feeMultiplier,
            decayFactor: decayFactor,
            volumeSensitivity: volumeSensitivity,
            timeSensitivity: timeSensitivity
        });

        emit FeeParametersUpdated(asset, feeParameters[asset]);
    }

    /**
     * @dev Get fee parameters for an asset
     */
    function getFeeParameters(address asset) external view returns (FeeParameters memory) {
        return feeParameters[asset];
    }

    /**
     * @dev Get current base rate for an asset (with decay applied)
     */
    function getCurrentBaseRate(address asset) external view returns (uint256) {
        return _getDecayedBaseRate(asset);
    }
}

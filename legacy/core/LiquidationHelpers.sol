// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/Math.sol";

/**
 * @title LiquidationHelpers
 * @dev Helper functions for complex liquidation logic matching Rust implementation
 */
library LiquidationHelpers {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MCR = 1.1e18; // 110%
    uint256 public constant CCR = 1.5e18; // 150%
    uint256 public constant LIQUIDATION_RESERVE = 200e18;
    uint256 public constant PERCENT_DIVISOR = 200;

    struct LiquidationValues {
        uint256 entireTroveDebt;
        uint256 entireTroveColl;
        uint256 collGasCompensation;
        uint256 debtToOffset;
        uint256 collToSendToSP;
        uint256 debtToRedistribute;
        uint256 collToRedistribute;
        uint256 collSurplus;
    }

    struct LiquidationTotals {
        uint256 totalCollInSequence;
        uint256 totalDebtInSequence;
        uint256 totalCollGasCompensation;
        uint256 totalDebtToOffset;
        uint256 totalCollToSendToSP;
        uint256 totalDebtToRedistribute;
        uint256 totalCollToRedistribute;
        uint256 totalCollSurplus;
    }

    /**
     * @dev Calculate liquidation values for normal mode
     */
    function calculateLiquidationValuesNormalMode(
        uint256 debt,
        uint256 coll,
        uint256 stabilityPoolUSDF,
        uint256 price
    ) external pure returns (LiquidationValues memory singleLiquidation) {
        singleLiquidation.entireTroveDebt = debt;
        singleLiquidation.entireTroveColl = coll;
        
        uint256 collToLiquidate = coll;
        
        // Calculate gas compensation
        singleLiquidation.collGasCompensation = _getCollGasCompensation(collToLiquidate, price);
        uint256 collToLiquidateAfterGasComp = collToLiquidate - singleLiquidation.collGasCompensation;
        
        if (stabilityPoolUSDF == 0) {
            // No stability pool - redistribute everything
            singleLiquidation.debtToOffset = 0;
            singleLiquidation.collToSendToSP = 0;
            singleLiquidation.debtToRedistribute = debt;
            singleLiquidation.collToRedistribute = collToLiquidateAfterGasComp;
            singleLiquidation.collSurplus = 0;
        } else {
            // Stability pool available
            uint256 debtToOffset = Math.min(debt, stabilityPoolUSDF);
            uint256 collToSendToSP = collToLiquidateAfterGasComp.mulDiv(debtToOffset, debt);
            
            singleLiquidation.debtToOffset = debtToOffset;
            singleLiquidation.collToSendToSP = collToSendToSP;
            singleLiquidation.debtToRedistribute = debt - debtToOffset;
            singleLiquidation.collToRedistribute = collToLiquidateAfterGasComp - collToSendToSP;
            singleLiquidation.collSurplus = 0;
        }
    }

    /**
     * @dev Calculate liquidation values for recovery mode
     */
    function calculateLiquidationValuesRecoveryMode(
        uint256 debt,
        uint256 coll,
        uint256 stabilityPoolUSDF,
        uint256 price,
        uint256 ICR
    ) external pure returns (LiquidationValues memory singleLiquidation) {
        singleLiquidation.entireTroveDebt = debt;
        singleLiquidation.entireTroveColl = coll;
        
        if (ICR <= 1e18) {
            // ICR <= 100% - liquidate entire trove
            // ICR <= 100% - liquidate entire trove using normal mode logic
            LiquidationValues memory singleLiquidation;
            singleLiquidation.entireTroveDebt = debt;
            singleLiquidation.entireTroveColl = coll;
            
            uint256 collToLiquidate = coll;
            
            // Calculate gas compensation
            singleLiquidation.collGasCompensation = _getCollGasCompensation(collToLiquidate, price);
            uint256 collToLiquidateAfterGasComp = collToLiquidate - singleLiquidation.collGasCompensation;
            
            if (stabilityPoolUSDF == 0) {
                // No stability pool - redistribute everything
                singleLiquidation.debtToOffset = 0;
                singleLiquidation.collToSendToSP = 0;
                singleLiquidation.debtToRedistribute = debt;
                singleLiquidation.collToRedistribute = collToLiquidateAfterGasComp;
                singleLiquidation.collSurplus = 0;
            } else {
                // Stability pool available
                uint256 debtToOffset = Math.min(debt, stabilityPoolUSDF);
                uint256 collToSendToSP = collToLiquidateAfterGasComp.mulDiv(debtToOffset, debt);
                
                singleLiquidation.debtToOffset = debtToOffset;
                singleLiquidation.collToSendToSP = collToSendToSP;
                singleLiquidation.debtToRedistribute = debt - debtToOffset;
                singleLiquidation.collToRedistribute = collToLiquidateAfterGasComp - collToSendToSP;
                singleLiquidation.collSurplus = 0;
            }
            
            return singleLiquidation;
        } else {
            // ICR > 100% but < MCR - partial liquidation
            uint256 maxLiquidatableDebt = coll.mulDiv(price, MCR);
            uint256 debtToLiquidate = Math.min(debt, maxLiquidatableDebt);
            uint256 collToLiquidate = debtToLiquidate.mulDiv(MCR, price);
            
            // Calculate gas compensation
            singleLiquidation.collGasCompensation = _getCollGasCompensation(collToLiquidate, price);
            uint256 collToLiquidateAfterGasComp = collToLiquidate - singleLiquidation.collGasCompensation;
            
            if (stabilityPoolUSDF == 0) {
                // No stability pool - redistribute
                singleLiquidation.debtToOffset = 0;
                singleLiquidation.collToSendToSP = 0;
                singleLiquidation.debtToRedistribute = debtToLiquidate;
                singleLiquidation.collToRedistribute = collToLiquidateAfterGasComp;
            } else {
                // Stability pool available
                uint256 debtToOffset = Math.min(debtToLiquidate, stabilityPoolUSDF);
                uint256 collToSendToSP = collToLiquidateAfterGasComp.mulDiv(debtToOffset, debtToLiquidate);
                
                singleLiquidation.debtToOffset = debtToOffset;
                singleLiquidation.collToSendToSP = collToSendToSP;
                singleLiquidation.debtToRedistribute = debtToLiquidate - debtToOffset;
                singleLiquidation.collToRedistribute = collToLiquidateAfterGasComp - collToSendToSP;
            }
            
            // Calculate surplus collateral
            singleLiquidation.collSurplus = coll - collToLiquidate;
        }
    }

    /**
     * @dev Add liquidation values to totals
     */
    function addLiquidationValuesToTotals(
        LiquidationTotals memory oldTotals,
        LiquidationValues memory singleLiquidation
    ) external pure returns (LiquidationTotals memory newTotals) {
        newTotals.totalCollInSequence = oldTotals.totalCollInSequence + singleLiquidation.entireTroveColl;
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence + singleLiquidation.entireTroveDebt;
        newTotals.totalCollGasCompensation = oldTotals.totalCollGasCompensation + singleLiquidation.collGasCompensation;
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset + singleLiquidation.debtToOffset;
        newTotals.totalCollToSendToSP = oldTotals.totalCollToSendToSP + singleLiquidation.collToSendToSP;
        newTotals.totalDebtToRedistribute = oldTotals.totalDebtToRedistribute + singleLiquidation.debtToRedistribute;
        newTotals.totalCollToRedistribute = oldTotals.totalCollToRedistribute + singleLiquidation.collToRedistribute;
        newTotals.totalCollSurplus = oldTotals.totalCollSurplus + singleLiquidation.collSurplus;
    }

    /**
     * @dev Calculate gas compensation for collateral
     */
    function _getCollGasCompensation(uint256 coll, uint256 price) internal pure returns (uint256) {
        uint256 gasCompensationInUSD = LIQUIDATION_RESERVE / 2; // 100 USDF worth
        return gasCompensationInUSD.mulDiv(DECIMAL_PRECISION, price);
    }

    /**
     * @dev Calculate Individual Collateral Ratio (ICR)
     */
    function calculateICR(uint256 coll, uint256 debt, uint256 price) external pure returns (uint256) {
        if (debt > 0) {
            return coll.mulDiv(price, debt);
        }
        return type(uint256).max;
    }

    /**
     * @dev Calculate Nominal Individual Collateral Ratio (NICR)
     */
    function calculateNICR(uint256 coll, uint256 debt) external pure returns (uint256) {
        if (debt > 0) {
            return coll.mulDiv(DECIMAL_PRECISION, debt);
        }
        return type(uint256).max;
    }

    /**
     * @dev Calculate Total Collateral Ratio (TCR)
     */
    function calculateTCR(uint256 totalColl, uint256 totalDebt, uint256 price) external pure returns (uint256) {
        if (totalDebt > 0) {
            return totalColl.mulDiv(price, totalDebt);
        }
        return type(uint256).max;
    }

    /**
     * @dev Check if trove is undercollateralized
     */
    function isUndercollateralized(uint256 ICR) external pure returns (bool) {
        return ICR < MCR;
    }

    /**
     * @dev Check if system is in recovery mode
     */
    function isRecoveryMode(uint256 TCR) external pure returns (bool) {
        return TCR < CCR;
    }

    /**
     * @dev Calculate borrowing fee
     */
    function calculateBorrowingFee(uint256 debt, uint256 baseRate) external pure returns (uint256) {
        uint256 borrowingRate = _getBorrowingRate(baseRate);
        return debt.mulDiv(borrowingRate, DECIMAL_PRECISION);
    }

    /**
     * @dev Calculate redemption fee
     */
    function calculateRedemptionFee(uint256 collAmount, uint256 baseRate) external pure returns (uint256) {
        uint256 redemptionRate = _getRedemptionRate(baseRate);
        return collAmount.mulDiv(redemptionRate, DECIMAL_PRECISION);
    }

    /**
     * @dev Get borrowing rate based on base rate
     */
    function _getBorrowingRate(uint256 baseRate) internal pure returns (uint256) {
        uint256 borrowingFeeFloor = DECIMAL_PRECISION / PERCENT_DIVISOR; // 0.5%
        return Math.max(borrowingFeeFloor, baseRate);
    }

    /**
     * @dev Get redemption rate based on base rate
     */
    function _getRedemptionRate(uint256 baseRate) internal pure returns (uint256) {
        uint256 redemptionFeeFloor = DECIMAL_PRECISION / PERCENT_DIVISOR; // 0.5%
        return Math.max(redemptionFeeFloor, baseRate);
    }

    /**
     * @dev Decay base rate based on time elapsed
     */
    function decayBaseRate(uint256 baseRate, uint256 timeElapsed) external pure returns (uint256) {
        uint256 minutesElapsed = timeElapsed / 60;
        uint256 decayFactor = _calculateDecayFactor(minutesElapsed);
        return baseRate.mulDiv(decayFactor, DECIMAL_PRECISION);
    }

    /**
     * @dev Calculate decay factor for base rate
     */
    function _calculateDecayFactor(uint256 minutesElapsed) internal pure returns (uint256) {
        if (minutesElapsed == 0) return DECIMAL_PRECISION;
        
        // Approximation: decayFactor = 0.999037758833783^minutesElapsed
        // For simplicity, using linear approximation for small values
        uint256 decayPerMinute = 962242; // approximately 0.000962242
        uint256 totalDecay = decayPerMinute * minutesElapsed;
        
        if (totalDecay >= DECIMAL_PRECISION) return 0;
        return DECIMAL_PRECISION - totalDecay;
    }

    /**
     * @dev Calculate new stake based on total stakes and collateral
     */
    function calculateNewStake(
        uint256 coll,
        uint256 totalStakes,
        uint256 totalCollateral
    ) external pure returns (uint256) {
        if (totalCollateral == 0) return coll;
        return coll.mulDiv(totalStakes, totalCollateral);
    }

    /**
     * @dev Calculate pending rewards for a trove
     */
    function calculatePendingRewards(
        uint256 stake,
        uint256 L_Collateral,
        uint256 L_Debt,
        uint256 snapshotCollateral,
        uint256 snapshotDebt
    ) external pure returns (uint256 pendingCollReward, uint256 pendingDebtReward) {
        if (stake == 0) return (0, 0);
        
        uint256 collRewardPerUnitStaked = L_Collateral - snapshotCollateral;
        uint256 debtRewardPerUnitStaked = L_Debt - snapshotDebt;
        
        pendingCollReward = stake.mulDiv(collRewardPerUnitStaked, DECIMAL_PRECISION);
        pendingDebtReward = stake.mulDiv(debtRewardPerUnitStaked, DECIMAL_PRECISION);
    }
}

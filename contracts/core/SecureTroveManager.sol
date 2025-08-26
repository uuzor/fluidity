// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../security/SecurityBase.sol";
import "../libraries/OptimizedDataStructures.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/IStabilityPool.sol";
import "../tokens/USDF.sol";
import "./PriceOracle.sol";
import "./SortedTroves.sol";

/**
 * @title SecureTroveManager
 * @dev Security-hardened TroveManager with comprehensive protections
 */
contract SecureTroveManager is SecurityBase, ITroveManager {
    using OptimizedDataStructures for OptimizedDataStructures.CircularBuffer;
    using OptimizedDataStructures for OptimizedDataStructures.PackedTrove;
    
    // Constants with explicit bounds checking
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MIN_COLLATERAL_RATIO = 1.35e18; // 135%
    uint256 public constant LIQUIDATION_THRESHOLD = 1.1e18; // 110%
    uint256 public constant CCR = 1.5e18; // Critical collateralization ratio
    uint256 public constant MCR = 1.1e18; // Minimum collateralization ratio
    uint256 public constant LIQUIDATION_RESERVE = 200e18; // 200 USDF
    uint256 public constant MAX_BORROWING_FEE = 0.05e18; // 5%
    
    // Security limits
    uint256 public constant MAX_TROVES_PER_USER = 10;
    uint256 public constant MAX_LIQUIDATION_AMOUNT = 1000000e18; // 1M USDF
    uint256 public constant MIN_LIQUIDATION_AMOUNT = 100e18; // 100 USDF
    
    // Optimized storage
    mapping(address => mapping(address => OptimizedDataStructures.PackedTrove)) public packedTroves;
    mapping(address => uint256) public userTroveCount;
    mapping(address => uint256) public totalStakes;
    mapping(address => uint256) public totalCollateral;
    mapping(address => uint256) public totalDebt;
    
    // Liquidation rewards with overflow protection
    mapping(address => uint256) public L_Collateral;
    mapping(address => uint256) public L_Debt;
    
    // Snapshots for reward calculations
    mapping(address => mapping(address => uint256)) public L_CollateralSnapshots;
    mapping(address => mapping(address => uint256)) public L_DebtSnapshots;
    mapping(address => mapping(address => uint256)) public troveStakes;
    
    // Contract references
    USDF public immutable usdfToken;
    IStabilityPool public immutable stabilityPool;
    PriceOracle public immutable priceOracle;
    SortedTroves public immutable sortedTroves;
    
    // Enhanced events with security context
    event TroveUpdatedSecure(
        address indexed borrower,
        address indexed asset,
        uint256 debt,
        uint256 coll,
        uint256 stake,
        TroveManagerOperation operation,
        uint256 gasUsed,
        uint256 blockNumber
    );
    
    event SecurityCheck(
        address indexed caller,
        string checkType,
        bool passed,
        string details
    );
    
    constructor(
        address _accessControl,
        address _usdfToken,
        address _stabilityPool,
        address _priceOracle,
        address _sortedTroves
    ) SecurityBase(_accessControl) {
        _validateAddress(_usdfToken);
        _validateAddress(_stabilityPool);
        _validateAddress(_priceOracle);
        _validateAddress(_sortedTroves);
        
        usdfToken = USDF(_usdfToken);
        stabilityPool = IStabilityPool(_stabilityPool);
        priceOracle = PriceOracle(_priceOracle);
        sortedTroves = SortedTroves(_sortedTroves);
    }
    
    /**
     * @dev Secure trove update with comprehensive validation
     */
    function updateTrove(
        address borrower,
        address asset,
        uint256 collChange,
        bool isCollIncrease,
        uint256 debtChange,
        bool isDebtIncrease
    ) external 
        onlyValidRole(accessControl.LIQUIDATOR_ROLE())
        whenContractNotPaused()
        secureNonReentrant()
        returns (uint256, uint256) 
    {
        uint256 gasStart = gasleft();
        
        // Input validation
        _validateAddress(borrower);
        _validateAddress(asset);
        
        // Security checks including packed storage limits
        _performSecurityChecks(borrower, asset, collChange, debtChange);
        _validateTroveOperationLimits(borrower, asset, collChange, debtChange);
        
        // Get current trove data
        OptimizedDataStructures.PackedTrove memory packed = packedTroves[borrower][asset];
        (uint256 debt, uint256 coll, uint256 lastUpdate, uint256 status) = packed.unpackTrove();
        
        // Apply pending rewards with overflow protection
        (uint256 pendingCollReward, uint256 pendingDebtReward) = _getPendingRewards(borrower, asset);
        coll = _safeAdd(coll, pendingCollReward);
        debt = _safeAdd(debt, pendingDebtReward);
        
        // Update collateral
        if (isCollIncrease) {
            coll = _safeAdd(coll, collChange);
        } else {
            coll = _safeSub(coll, collChange);
        }
        
        // Update debt
        if (isDebtIncrease) {
            debt = _safeAdd(debt, debtChange);
        } else {
            debt = _safeSub(debt, debtChange);
        }
        
        // Validate final state
        _validateTroveState(borrower, asset, debt, coll);
        
        // Validate packed trove limits before storage
        _validatePackedTroveLimits(debt, coll);
        
        // Update storage with packed data
        packedTroves[borrower][asset] = OptimizedDataStructures.packTrove(
            debt,
            coll,
            block.timestamp,
            debt == 0 ? 2 : 1 // closedByOwner : active
        );
        
        // Get current trove data before applying rewards
        (uint256 currentDebt, uint256 currentColl,,) = _getTroveData(borrower, asset);
        
        // Update global totals based on changes
        _updateGlobalTotalsOnTroveChange(asset, currentDebt, currentColl, debt, coll);
        
        // Update stake for this trove
        uint256 newStake = _calculateStake(asset, debt, coll);
        troveStakes[borrower][asset] = newStake;
        
        // Update snapshots for reward calculations
        _updateTroveSnapshots(borrower, asset);
        
        // Update sorted troves position
        uint256 newICR = debt > 0 ? _calculateICR(coll, debt, _getFreshPrice(asset)) : type(uint256).max;
        if (packed.status == 0) {
            // New trove
            sortedTroves.insert(asset, borrower, newICR, address(0), address(0));
            userTroveCount[borrower]++;
        } else if (debt == 0) {
            // Trove is being closed
            sortedTroves.remove(asset, borrower);
            userTroveCount[borrower]--;
        } else {
            // Existing trove with debt - update position
            sortedTroves.reInsert(asset, borrower, newICR, address(0), address(0));
        }
        
        uint256 gasUsed = gasStart - gasleft();
        emit TroveUpdatedSecure(
            borrower,
            asset,
            debt,
            coll,
            0, // stake calculation
            TroveManagerOperation.updateTrove,
            gasUsed,
            block.number
        );
        
        return (debt, coll);
    }
    
    /**
     * @dev Secure liquidation with circuit breakers
     */
    function liquidate(
        address borrower,
        address asset
    ) external 
        onlyValidRole(accessControl.LIQUIDATOR_ROLE())
        whenContractNotPaused()
        liquidationCircuitBreaker()
        secureNonReentrant()
    {
        // Validate liquidation conditions
        _validateLiquidation(borrower, asset);
        
        // Get trove data
        (uint256 debt, uint256 coll,,) = _getTroveData(borrower, asset);
        
        // Validate liquidation amount bounds
        require(debt >= MIN_LIQUIDATION_AMOUNT, "Liquidation amount too small");
        require(debt <= MAX_LIQUIDATION_AMOUNT, "Liquidation amount too large");
        
        // Calculate ICR with fresh price
        uint256 price = _getFreshPrice(asset);
        uint256 ICR = _calculateICR(coll, debt, price);
        
        require(ICR < MCR, "Trove not undercollateralized");
        
        // Execute liquidation with security monitoring
        _executeLiquidation(borrower, asset, debt, coll, price);
        
        emit SecurityCheck(
            msg.sender,
            "liquidation",
            true,
            "Liquidation executed successfully"
        );
    }
    
    /**
     * @dev Batch liquidation with enhanced security
     */
    function batchLiquidateTroves(
        address asset,
        address[] memory borrowers
    ) external 
        onlyValidRole(accessControl.LIQUIDATOR_ROLE())
        whenContractNotPaused()
        secureNonReentrant()
        returns (uint256 totalLiquidated, uint256 totalDebtLiquidated, uint256 totalCollLiquidated)
    {
        require(borrowers.length > 0, "Empty borrowers array");
        require(borrowers.length <= 20, "Too many liquidations in batch");
        
        uint256 price = _getFreshPrice(asset);
        totalLiquidated = 0;
        totalDebtLiquidated = 0;
        totalCollLiquidated = 0;
        
        // Track which liquidations failed and why
        uint256 failedCount = 0;
        
        for (uint256 i = 0; i < borrowers.length; i++) {
            address borrower = borrowers[i];
            
            // Pre-validate before attempting liquidation
            if (_canLiquidate(borrower, asset, price)) {
                try this.liquidate(borrower, asset) {
                    totalLiquidated++;
                    
                    // Get liquidated amounts for reporting
                    // Note: In real implementation, these would be returned from liquidate()
                    (uint256 debt, uint256 coll,,) = _getTroveData(borrower, asset);
                    totalDebtLiquidated = _safeAdd(totalDebtLiquidated, debt);
                    totalCollLiquidated = _safeAdd(totalCollLiquidated, coll);
                    
                } catch Error(string memory reason) {
                    failedCount++;
                    emit SecurityCheck(
                        msg.sender,
                        "batch_liquidation_item_failed",
                        false,
                        string(abi.encodePacked("Liquidation failed: ", reason))
                    );
                } catch (bytes memory lowLevelData) {
                    failedCount++;
                    emit SecurityCheck(
                        msg.sender,
                        "batch_liquidation_low_level_error",
                        false,
                        "Low-level liquidation error"
                    );
                }
            } else {
                failedCount++;
                emit SecurityCheck(
                    msg.sender,
                    "batch_liquidation_invalid_trove",
                    false,
                    "Trove cannot be liquidated"
                );
            }
        }
        
        require(totalLiquidated > 0, "No liquidations executed");
        
        // Emit comprehensive batch result
        emit SecurityCheck(
            msg.sender,
            "batch_liquidation_complete",
            true,
            string(abi.encodePacked(
                "Liquidated: ", _uintToString(totalLiquidated),
                ", Failed: ", _uintToString(failedCount)
            ))
        );
        
        return (totalLiquidated, totalDebtLiquidated, totalCollLiquidated);
    }
    
    /**
     * @dev Security validation functions
     */
    function _performSecurityChecks(
        address borrower,
        address asset,
        uint256 collChange,
        uint256 debtChange
    ) internal {
        // Check user trove limits
        if (packedTroves[borrower][asset].status == 0) { // New trove
            require(
                userTroveCount[borrower] < MAX_TROVES_PER_USER,
                "Too many troves per user"
            );
        }
        
        // Validate reasonable amounts
        require(collChange <= 10000e18, "Collateral change too large");
        require(debtChange <= 1000000e18, "Debt change too large");
        
        emit SecurityCheck(borrower, "trove_limits", true, "Security checks passed");
    }
    
    function _validateLiquidation(address borrower, address asset) internal view {
        OptimizedDataStructures.PackedTrove memory packed = packedTroves[borrower][asset];
        require(packed.status != 0, "Trove does not exist");
        require(packed.status == 1, "Trove not active"); // Assuming 1 = active
    }
    
    function _validateTroveState(
        address borrower,
        address asset,
        uint256 debt,
        uint256 coll
    ) internal {
        if (debt > 0) {
            uint256 price = _getFreshPrice(asset);
            uint256 ICR = _calculateICR(coll, debt, price);
            require(ICR >= MCR, "ICR below minimum");
        }
    }
    
    function _getFreshPrice(address asset) internal view returns (uint256) {
        uint256 price = priceOracle.getPrice(asset);
        require(price > 0, "Invalid price");
        return price;
    }
    
    function _calculateICR(
        uint256 coll,
        uint256 debt,
        uint256 price
    ) internal pure returns (uint256) {
        if (debt == 0) return type(uint256).max;
        return (coll * price) / debt;
    }
    
    function _getPendingRewards(
        address borrower,
        address asset
    ) internal view returns (uint256 collReward, uint256 debtReward) {
        uint256 stake = troveStakes[borrower][asset];
        if (stake == 0) {
            return (0, 0);
        }
        
        uint256 L_CollSnapshot = L_CollateralSnapshots[borrower][asset];
        uint256 L_DebtSnapshot = L_DebtSnapshots[borrower][asset];
        
        // Calculate pending rewards based on stake and reward per unit staked
        collReward = _safeMul(stake, _safeSub(L_Collateral[asset], L_CollSnapshot)) / DECIMAL_PRECISION;
        debtReward = _safeMul(stake, _safeSub(L_Debt[asset], L_DebtSnapshot)) / DECIMAL_PRECISION;
        
        return (collReward, debtReward);
    }
    
    function _getTroveData(
        address borrower,
        address asset
    ) internal view returns (uint256 debt, uint256 coll, uint256 lastUpdate, uint256 status) {
        OptimizedDataStructures.PackedTrove memory packed = packedTroves[borrower][asset];
        return packed.unpackTrove();
    }
    
    function _executeLiquidation(
        address borrower,
        address asset,
        uint256 debt,
        uint256 coll,
        uint256 price
    ) internal {
        // Apply pending rewards first
        (uint256 pendingCollReward, uint256 pendingDebtReward) = _getPendingRewards(borrower, asset);
        uint256 totalTroveDebt = _safeAdd(debt, pendingDebtReward);
        uint256 totalColl = _safeAdd(coll, pendingCollReward);
        
        // Determine liquidation mode based on system state
        uint256 TCR = _getTCR(asset, price);
        bool isInRecoveryMode = TCR < CCR;
        
        uint256 debtToOffset;
        uint256 collToSendToSP;
        uint256 debtToRedistribute;
        uint256 collToRedistribute;
        
        if (isInRecoveryMode && totalColl * price >= totalTroveDebt) {
            // In recovery mode with sufficient collateral - full liquidation to stability pool
            debtToOffset = totalTroveDebt;
            collToSendToSP = totalColl;
            debtToRedistribute = 0;
            collToRedistribute = 0;
        } else {
            // Normal mode or insufficient collateral - check stability pool capacity
            uint256 stabilityPoolDebt = stabilityPool.getTotalUSDF();
            
            if (stabilityPoolDebt >= totalTroveDebt) {
                // Stability pool can absorb all debt
                debtToOffset = totalTroveDebt;
                collToSendToSP = totalColl;
                debtToRedistribute = 0;
                collToRedistribute = 0;
            } else {
                // Split between stability pool and redistribution
                debtToOffset = stabilityPoolDebt;
                collToSendToSP = (totalColl * debtToOffset) / totalTroveDebt;
                debtToRedistribute = totalTroveDebt - debtToOffset;
                collToRedistribute = totalColl - collToSendToSP;
            }
        }
        
        // Close the trove
        packedTroves[borrower][asset] = OptimizedDataStructures.packTrove(
            0, 0, block.timestamp, 3 // closedByLiquidation
        );
        
        // Remove from sorted troves
        sortedTroves.remove(asset, borrower);
        userTroveCount[borrower]--;
        
        // Update global totals
        totalDebt[asset] = _safeSub(totalDebt[asset], totalTroveDebt);
        totalCollateral[asset] = _safeSub(totalCollateral[asset], totalColl);
        
        // Update total stakes
        uint256 stake = troveStakes[borrower][asset];
        totalStakes[asset] = _safeSub(totalStakes[asset], stake);
        troveStakes[borrower][asset] = 0;
        
        // Distribute liquidation rewards
        _distributeLiquidationRewards(
            asset,
            debtToOffset,
            collToSendToSP,
            debtToRedistribute,
            collToRedistribute
        );
        
        emit TroveLiquidated(
            borrower, 
            asset, 
            totalTroveDebt, 
            totalColl, 
            isInRecoveryMode ? TroveManagerOperation.liquidateInRecoveryMode : TroveManagerOperation.liquidateInNormalMode
        );
    }
    
    function _getTCR(address asset, uint256 price) internal view returns (uint256) {
        uint256 entireSystemColl = totalCollateral[asset];
        uint256 entireSystemDebt = totalDebt[asset];
        
        if (entireSystemDebt == 0) {
            return type(uint256).max;
        }
        
        return (entireSystemColl * price) / entireSystemDebt;
    }
    
    function _updateGlobalTotals(address asset, uint256 newDebt, uint256 newColl) internal {
        // This function should be called after calculating the new total debt and collateral
        // for a specific trove update, not for setting absolute values
        totalDebt[asset] = newDebt;
        totalCollateral[asset] = newColl;
    }
    
    function _updateGlobalTotalsOnTroveChange(
        address asset, 
        uint256 oldDebt, 
        uint256 oldColl, 
        uint256 newDebt, 
        uint256 newColl
    ) internal {
        // Update global totals based on the change in trove values
        if (newDebt >= oldDebt) {
            totalDebt[asset] = _safeAdd(totalDebt[asset], newDebt - oldDebt);
        } else {
            totalDebt[asset] = _safeSub(totalDebt[asset], oldDebt - newDebt);
        }
        
        if (newColl >= oldColl) {
            totalCollateral[asset] = _safeAdd(totalCollateral[asset], newColl - oldColl);
        } else {
            totalCollateral[asset] = _safeSub(totalCollateral[asset], oldColl - newColl);
        }
    }
    
    /**
     * @dev View functions for external access
     */
    function getCurrentICR(address borrower, address asset) external view returns (uint256) {
        (uint256 debt, uint256 coll,,) = _getTroveData(borrower, asset);
        if (debt == 0) return type(uint256).max;
        
        uint256 price = priceOracle.getPrice(asset);
        return _calculateICR(coll, debt, price);
    }
    
    function getTroveDebtAndColl(
        address borrower,
        address asset
    ) external view returns (uint256 debt, uint256 coll) {
        (debt, coll,,) = _getTroveData(borrower, asset);
    }
    
    function getTroveStatus(address borrower, address asset) external view returns (uint256) {
        (,,, uint256 status) = _getTroveData(borrower, asset);
        return status;
    }
    
    // Remove override keywords as they're causing conflicts
    // These functions are defined in the interface but may not need override
    // function totalStakes(address asset) external view returns (uint256) {
    //     return totalStakes[asset];
    // }
    
    // function totalCollateral(address asset) external view returns (uint256) {
    //     return totalCollateral[asset];
    // }
    
    // function totalDebt(address asset) external view returns (uint256) {
    //     return totalDebt[asset];
    // }
    
    /**
     * @dev Missing interface implementations
     */
    function liquidateTroves(address asset, uint256 n) external 
        whenContractNotPaused()
        secureNonReentrant()
        onlyValidRole(accessControl.LIQUIDATOR_ROLE())
    {
        require(n > 0, "Must liquidate at least 1 trove");
        require(n <= 50, "Too many troves to liquidate at once");
        
        uint256 price = _getFreshPrice(asset);
        uint256 liquidatedCount = 0;
        uint256 totalLiquidatedDebt = 0;
        uint256 totalLiquidatedColl = 0;
        
        // Get sorted list of troves from lowest to highest ICR
        address currentTrove = sortedTroves.getFirst(asset);
        
        for (uint256 i = 0; i < n && currentTrove != address(0); i++) {
            address nextTrove = sortedTroves.getNext(asset, currentTrove);
            
            // Check if trove is undercollateralized
            (uint256 debt, uint256 coll,,) = _getTroveData(currentTrove, asset);
            if (debt > 0) {
                uint256 ICR = _calculateICR(coll, debt, price);
                
                if (ICR < MCR) {
                    try this.liquidate(currentTrove, asset) {
                        liquidatedCount++;
                        totalLiquidatedDebt = _safeAdd(totalLiquidatedDebt, debt);
                        totalLiquidatedColl = _safeAdd(totalLiquidatedColl, coll);
                    } catch {
                        // Continue to next trove if liquidation fails
                        emit SecurityCheck(
                            msg.sender,
                            "liquidation_failed",
                            false,
                            "Individual trove liquidation failed"
                        );
                    }
                } else {
                    // Troves are sorted by ICR, so if current trove is sufficiently collateralized,
                    // all remaining troves will be too
                    break;
                }
            }
            
            currentTrove = nextTrove;
        }
        
        require(liquidatedCount > 0, "No troves were liquidated");
        
        emit SecurityCheck(
            msg.sender, 
            "batch_liquidation_complete", 
            true, 
            string(abi.encodePacked("Liquidated ", _uintToString(liquidatedCount), " troves"))
        );
    }
    
    function redeemCollateral(
        address asset,
        uint256 usdfAmount,
        address firstRedemptionHint,
        address upperPartialRedemptionHint,
        address lowerPartialRedemptionHint,
        uint256 partialRedemptionHintNICR,
        uint256 maxIterations,
        uint256 maxFeePercentage
    ) external 
        whenContractNotPaused()
        secureNonReentrant()
    {
        require(usdfAmount > 0, "USDF amount must be positive");
        require(maxIterations > 0 && maxIterations <= 50, "Invalid max iterations");
        require(maxFeePercentage <= MAX_BORROWING_FEE, "Max fee percentage too high");
        require(usdfToken.balanceOf(msg.sender) >= usdfAmount, "Insufficient USDF balance");
        
        uint256 price = _getFreshPrice(asset);
        uint256 remainingUSDF = usdfAmount;
        uint256 totalCollateralRedeemed = 0;
        uint256 iterations = 0;
        
        // Start from the trove with the lowest ICR (first in sorted list)
        address currentTrove = firstRedemptionHint != address(0) ? 
            firstRedemptionHint : sortedTroves.getLast(asset); // Start from highest ICR for redemption
            
        while (remainingUSDF > 0 && currentTrove != address(0) && iterations < maxIterations) {
            (uint256 debt, uint256 coll,,) = _getTroveData(currentTrove, asset);
            
            if (debt > 0) {
                uint256 ICR = _calculateICR(coll, debt, price);
                require(ICR >= MCR, "Cannot redeem from undercollateralized trove");
                
                uint256 maxRedeemableDebt = debt > LIQUIDATION_RESERVE ? 
                    debt - LIQUIDATION_RESERVE : 0;
                    
                if (maxRedeemableDebt > 0) {
                    uint256 debtToRedeem = remainingUSDF > maxRedeemableDebt ? 
                        maxRedeemableDebt : remainingUSDF;
                    
                    // Calculate collateral to redeem
                    uint256 collToRedeem = (debtToRedeem * DECIMAL_PRECISION) / price;
                    
                    if (collToRedeem <= coll) {
                        // Update trove
                        uint256 newDebt = debt - debtToRedeem;
                        uint256 newColl = coll - collToRedeem;
                        
                        // Update trove storage
                        packedTroves[currentTrove][asset] = OptimizedDataStructures.packTrove(
                            newDebt,
                            newColl,
                            block.timestamp,
                            newDebt == 0 ? 4 : 1 // closedByRedemption : active
                        );
                        
                        // Update global totals
                        totalDebt[asset] = _safeSub(totalDebt[asset], debtToRedeem);
                        totalCollateral[asset] = _safeSub(totalCollateral[asset], collToRedeem);
                        
                        // Update sorted troves if trove still has debt
                        if (newDebt > 0) {
                            uint256 newICR = _calculateICR(newColl, newDebt, price);
                            sortedTroves.reInsert(asset, currentTrove, newICR, upperPartialRedemptionHint, lowerPartialRedemptionHint);
                        } else {
                            sortedTroves.remove(asset, currentTrove);
                            userTroveCount[currentTrove]--;
                        }
                        
                        remainingUSDF = _safeSub(remainingUSDF, debtToRedeem);
                        totalCollateralRedeemed = _safeAdd(totalCollateralRedeemed, collToRedeem);
                        
                        emit TroveUpdated(
                            currentTrove,
                            asset,
                            newDebt,
                            newColl,
                            0, // stake
                            TroveManagerOperation.redeemCollateral
                        );
                    }
                }
            }
            
            currentTrove = sortedTroves.getPrev(asset, currentTrove);
            iterations++;
        }
        
        require(remainingUSDF < usdfAmount, "No redemption occurred");
        
        uint256 actualUSDFRedeemed = usdfAmount - remainingUSDF;
        
        // Calculate and charge redemption fee
        uint256 redemptionFee = _calculateRedemptionFee(actualUSDFRedeemed);
        uint256 collateralAfterFee = totalCollateralRedeemed > redemptionFee ? 
            totalCollateralRedeemed - redemptionFee : 0;
            
        require(redemptionFee <= (totalCollateralRedeemed * maxFeePercentage) / DECIMAL_PRECISION, "Fee exceeds maximum");
        
        // Burn USDF from redeemer
        usdfToken.burnFrom(msg.sender, actualUSDFRedeemed);
        
        // Transfer collateral to redeemer (implementation would depend on asset type)
        // This would typically involve transferring the actual collateral tokens
        
        emit Redemption(msg.sender, actualUSDFRedeemed, collateralAfterFee, redemptionFee);
    }

    function _updateTroveSnapshots(address borrower, address asset) internal {
        L_CollateralSnapshots[borrower][asset] = L_Collateral[asset];
        L_DebtSnapshots[borrower][asset] = L_Debt[asset];
    }
    
    function _calculateStake(address asset, uint256 debt, uint256 coll) internal view returns (uint256) {
        if (totalCollateral[asset] == 0) {
            return coll;
        }
        
        // Stake is proportional to the trove's collateral relative to total collateral
        return (coll * totalStakes[asset]) / totalCollateral[asset];
    }
    
    function _calculateRedemptionFee(uint256 usdfAmount) internal view returns (uint256) {
        // Simple redemption fee calculation - typically 0.5% to 5% based on recent redemptions
        // This is a simplified implementation; production systems would use more complex fee curves
        uint256 baseRate = 0.005e18; // 0.5% base rate
        return (usdfAmount * baseRate) / DECIMAL_PRECISION;
    }
    
    function _canLiquidate(address borrower, address asset, uint256 price) internal view returns (bool) {
        (uint256 debt, uint256 coll,, uint256 status) = _getTroveData(borrower, asset);
        
        // Check if trove exists and is active
        if (status != 1 || debt == 0) {
            return false;
        }
        
        // Check if trove is undercollateralized
        uint256 ICR = _calculateICR(coll, debt, price);
        if (ICR >= MCR) {
            return false;
        }
        
        // Check debt bounds
        if (debt < MIN_LIQUIDATION_AMOUNT || debt > MAX_LIQUIDATION_AMOUNT) {
            return false;
        }
        
        return true;
    }
    
    function _validatePackedTroveLimits(uint256 debt, uint256 coll) internal pure {
        // Check if values exceed uint128 limits
        require(debt <= type(uint128).max, "Debt exceeds packed storage limit");
        require(coll <= type(uint128).max, "Collateral exceeds packed storage limit");
        
        // Additional reasonable limits for DeFi context
        // These limits prevent economic attacks and ensure reasonable trove sizes
        require(debt <= 1e9 * 1e18, "Debt exceeds maximum reasonable limit"); // 1 billion tokens
        require(coll <= 1e9 * 1e18, "Collateral exceeds maximum reasonable limit"); // 1 billion tokens
    }
    
    function _validateTroveOperationLimits(address borrower, address asset, uint256 collChange, uint256 debtChange) internal view {
        // Get current trove data
        (uint256 currentDebt, uint256 currentColl,,) = _getTroveData(borrower, asset);
        
        // Calculate potential new values
        uint256 maxPotentialDebt = currentDebt + debtChange;
        uint256 maxPotentialColl = currentColl + collChange;
        
        // Validate against packed limits
        require(maxPotentialDebt <= type(uint128).max, "Operation would exceed debt storage limit");
        require(maxPotentialColl <= type(uint128).max, "Operation would exceed collateral storage limit");
    }
    
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _distributeLiquidationRewards(
        address asset,
        uint256 debtToOffset,
        uint256 collToSendToSP,
        uint256 debtToRedistribute,
        uint256 collToRedistribute
    ) internal {
        if (debtToOffset > 0) {
            // Send to stability pool
            stabilityPool.offset(asset, debtToOffset, collToSendToSP);
        }
        
        if (debtToRedistribute > 0 && totalStakes[asset] > 0) {
            // Redistribute to remaining troves
            uint256 collRewardPerUnitStaked = (collToRedistribute * DECIMAL_PRECISION) / totalStakes[asset];
            uint256 debtRewardPerUnitStaked = (debtToRedistribute * DECIMAL_PRECISION) / totalStakes[asset];
            
            L_Collateral[asset] = _safeAdd(L_Collateral[asset], collRewardPerUnitStaked);
            L_Debt[asset] = _safeAdd(L_Debt[asset], debtRewardPerUnitStaked);
        }
    }
    
    /**
     * @dev Emergency functions
     */
    function emergencyShutdown() external onlyValidRole(accessControl.EMERGENCY_ROLE()) {
        _pause();
        emit SecurityCheck(msg.sender, "emergency_shutdown", true, "System paused");
    }
}

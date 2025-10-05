// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "../interfaces/ITroveManager.sol";
// import "../interfaces/IStabilityPool.sol";
// import "../interfaces/IRiskEngine.sol";
// import "../tokens/USDF.sol";
// import "../libraries/Math.sol";
// import "./LiquidationHelpers.sol";
// import "./PriceOracle.sol";
// import "./SortedTroves.sol";

// /**
//  * @title TroveManager
//  * @dev Manages individual troves (collateralized debt positions)
//  */
// contract TroveManager is ITroveManager, Ownable, ReentrancyGuard {
//     using Math for uint256;
//     using SafeERC20 for IERC20;

//     // Constants
//     uint256 public constant DECIMAL_PRECISION = 1e18;
//     uint256 public constant MIN_COLLATERAL_RATIO = 1.35e18; // 135%
//     uint256 public constant LIQUIDATION_THRESHOLD = 1.1e18; // 110%
//     uint256 public constant MAX_BORROWING_FEE = 0.05e18; // 5%
//     uint256 public constant REDEMPTION_FEE_FLOOR = 0.005e18; // 0.5%
//     uint256 public constant CCR = 1.5e18; // Critical collateralization ratio for recovery mode
//     uint256 public constant MCR = 1.1e18; // Minimum collateralization ratio
//     uint256 public constant LIQUIDATION_RESERVE = 200e18; // 200 USDF
//     uint256 public constant MAX_BORROWING_FEE_RECOVERY_MODE = 0; // No borrowing fee in recovery mode
//     uint256 public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%
//     uint256 public constant SECONDS_IN_ONE_MINUTE = 60;
//     uint256 public constant MINUTE_DECAY_FACTOR = 999037758833783000;

//     // State variables
//     mapping(address => mapping(address => Trove)) public troves; // user => asset => trove
//     mapping(address => uint256) public totalStakes; // asset => total stakes
//     mapping(address => uint256) public totalCollateral; // asset => total collateral
//     mapping(address => uint256) public totalCollateralSnapshot; // asset => total collateral snapshot
//     mapping(address => uint256) public totalStakesSnapshot; // asset => total stakes snapshot
//     mapping(address => uint256) public totalDebt; // asset => total debt
//     mapping(address => uint256) public lastFeeOperationTime; // asset => timestamp
    
//     // Liquidation rewards per unit staked
//     mapping(address => uint256) public L_Collateral; // asset => liquidation collateral reward per unit staked
//     mapping(address => uint256) public L_Debt; // asset => liquidation debt reward per unit staked
    
//     // Error tracking for reward distribution
//     mapping(address => uint256) public lastCollateralError_Redistribution;
//     mapping(address => uint256) public lastDebtError_Redistribution;
    
//     // Redemption tracking
//     mapping(address => uint256) public baseRate; // asset => base rate for fees
    
//     // Recovery mode tracking
//     mapping(address => bool) public recoveryMode;
    
//     // Contract references
//     USDF public usdfToken;
//     IStabilityPool public stabilityPool;
//     PriceOracle public priceOracle;
//     SortedTroves public sortedTroves;
//     address public borrowerOperations;
//     address public activePool;
//     address public defaultPool;
//     address public collSurplusPool;
//     address public gasPool;
    
//     // Liquidation structs
//     struct LiquidationValues {
//         uint256 entireTroveDebt;
//         uint256 entireTroveColl;
//         uint256 collGasCompensation;
//         uint256 debtToOffset;
//         uint256 collToSendToSP;
//         uint256 debtToRedistribute;
//         uint256 collToRedistribute;
//         uint256 collSurplus;
//     }
    
//     struct LiquidationTotals {
//         uint256 totalCollInSequence;
//         uint256 totalDebtInSequence;
//         uint256 totalCollGasCompensation;
//         uint256 totalDebtToOffset;
//         uint256 totalCollToSendToSP;
//         uint256 totalDebtToRedistribute;
//         uint256 totalCollToRedistribute;
//         uint256 totalCollSurplus;
//     }
    
//     struct LocalVariablesInnerSingleLiquidateFunction {
//         uint256 collToLiquidate;
//         uint256 pendingDebtReward;
//         uint256 pendingCollReward;
//     }
    
//     struct LocalVariablesLiquidationSequence {
//         uint256 remainingUSDF;
//         uint256 i;
//         uint256 ICR;
//         address user;
//         bool backToNormalMode;
//         uint256 entireSystemDebt;
//         uint256 entireSystemColl;
//         uint256 price;
//     }
    
//     // Additional events
//     event SystemSnapshotsUpdated(address indexed asset, uint256 totalStakesSnapshot, uint256 totalCollateralSnapshot);
//     event LTermsUpdated(address indexed asset, uint256 L_Collateral, uint256 L_Debt);
//     event TroveSnapshotsUpdated(address indexed borrower, address indexed asset, uint256 L_Collateral, uint256 L_Debt);
//     event TroveIndexUpdated(address indexed borrower, address indexed asset, uint256 newIndex);
//     event BaseRateUpdated(address indexed asset, uint256 newBaseRate);
//     event LastFeeOpTimeUpdated(address indexed asset, uint256 timestamp);
//     event TotalStakesUpdated(address indexed asset, uint256 newTotalStakes);
//     event RecoveryModeEntered(address indexed asset);
//     event RecoveryModeExited(address indexed asset);
//     event Liquidation(address indexed asset, uint256 liquidatedDebt, uint256 liquidatedColl, uint256 collGasCompensation);
//     event TroveClosed(address indexed borrower, address indexed asset);

//     modifier onlyBorrowerOperations() {
//         require(msg.sender == borrowerOperations, "Only BorrowerOperations");
//         _;
//     }

//     constructor() Ownable(msg.sender) {}

//     function initialize(
//         address _usdfToken,
//         address _stabilityPool,
//         address _priceOracle,
//         address _sortedTroves,
//         address _borrowerOperations,
//         address _activePool,
//         address _defaultPool,
//         address _collSurplusPool,
//         address _gasPool
//     ) external onlyOwner {
//         usdfToken = USDF(_usdfToken);
//         stabilityPool = IStabilityPool(_stabilityPool);
//         priceOracle = PriceOracle(_priceOracle);
//         sortedTroves = SortedTroves(_sortedTroves);
//         borrowerOperations = _borrowerOperations;
//         activePool = _activePool;
//         defaultPool = _defaultPool;
//         collSurplusPool = _collSurplusPool;
//         gasPool = _gasPool;
//     }

//     /**
//      * @dev Update trove with new debt and collateral amounts
//      */
//     function updateTrove(
//         address borrower,
//         address asset,
//         uint256 collChange,
//         bool isCollIncrease,
//         uint256 debtChange,
//         bool isDebtIncrease
//     ) external onlyBorrowerOperations returns (uint256, uint256) {
//         Trove storage trove = troves[borrower][asset];
        
//         uint256 oldDebt = trove.debt;
//         uint256 oldColl = trove.coll;
        
//         // If this is a new trove (status is nonExistent), set it to active
//         if (trove.status == Status.nonExistent) {
//             trove.status = Status.active;
//         }
        
//         // Apply pending rewards
//         _applyPendingRewards(borrower, asset);
        
//         // Update collateral
//         if (isCollIncrease) {
//             trove.coll = trove.coll + collChange;
//         } else {
//             trove.coll = trove.coll - collChange;
//         }
        
//         // Update debt
//         if (isDebtIncrease) {
//             trove.debt = trove.debt + debtChange;
//         } else {
//             trove.debt = trove.debt - debtChange;
//         }
        
//         // If trove debt becomes 0, close the trove
//         if (trove.debt == 0 && trove.coll == 0) {
//             trove.status = Status.closedByOwner;
//         }
        
//         // Update stake
//         uint256 newStake = _computeNewStake(asset, trove.coll);
//         uint256 oldStake = trove.stake;
//         trove.stake = newStake;
        
//         // Update global totals
//         totalStakes[asset] = totalStakes[asset] - oldStake + newStake;
//         totalCollateral[asset] = totalCollateral[asset] - oldColl + trove.coll;
//         totalDebt[asset] = totalDebt[asset] - oldDebt + trove.debt;
        
//         // Update snapshots for reward calculations
//         trove.L_CollateralSnapshot = L_Collateral[asset];
//         trove.L_DebtSnapshot = L_Debt[asset];
        
//         emit TroveUpdated(borrower, asset, trove.debt, trove.coll, trove.stake, TroveManagerOperation.updateTrove);
        
//         return (trove.debt, trove.coll);
//     }

//     /**
//      * @dev Liquidate a single trove with comprehensive logic
//      */
//     function liquidate(address borrower, address asset) external nonReentrant {
//         _requireTroveIsActive(borrower, asset);
        
//         address[] memory borrowers = new address[](1);
//         borrowers[0] = borrower;
//         batchLiquidateTroves(asset, borrowers);
//     }
    
//     /**
//      * @dev Batch liquidate multiple troves
//      */
//     function batchLiquidateTroves(address asset, address[] memory borrowers) public nonReentrant {
//         require(borrowers.length != 0, "TroveManager: Calldata address array must not be empty");
        
//         IStabilityPool stabilityPoolCached = stabilityPool;
//         uint256 price = priceOracle.getPrice(asset);
        
//         LocalVariablesLiquidationSequence memory vars;
//         LiquidationTotals memory totals;
        
//         vars.price = price;
//         vars.remainingUSDF = stabilityPoolCached.getTotalUSDF();
//         vars.backToNormalMode = !_checkRecoveryMode(asset, price);
        
//         for (vars.i = 0; vars.i < borrowers.length; vars.i++) {
//             vars.user = borrowers[vars.i];
//             vars.ICR = getCurrentICR(vars.user, asset);
            
//             if (!vars.backToNormalMode) {
//                 // Recovery mode liquidation
//                 if (vars.ICR < MCR) {
//                     vars.remainingUSDF = _liquidateRecoveryMode(stabilityPoolCached, asset, vars.user, vars.remainingUSDF, totals, vars.price);
//                 }
//             } else {
//                 // Normal mode liquidation
//                 if (vars.ICR < MCR) {
//                     vars.remainingUSDF = _liquidateNormalMode(stabilityPoolCached, asset, vars.user, vars.remainingUSDF, totals, vars.price);
//                 }
//             }
//         }
        
//         require(totals.totalDebtInSequence > 0, "TroveManager: nothing to liquidate");
        
//         // Move liquidated collateral and debt to the appropriate pools
//         _finalizeLiquidation(
//             stabilityPoolCached,
//             asset,
//             totals,
//             vars.price
//         );
        
//         emit Liquidation(asset, totals.totalDebtInSequence, totals.totalCollInSequence, totals.totalCollGasCompensation);
//     }

//     // Internal helper functions
//     function _requireTroveIsActive(address borrower, address asset) internal view {
//         require(troves[borrower][asset].status == Status.active, "Trove is not active");
//     }

//     function _liquidateRecoveryMode(
//         IStabilityPool stabilityPoolCached,
//         address asset,
//         address borrower,
//         uint256 remainingUSDF,
//         LiquidationTotals memory totals,
//         uint256 price
//     ) internal returns (uint256) {
//         Trove memory trove = troves[borrower][asset];
//         uint256 ICR = LiquidationHelpers.calculateICR(trove.coll, trove.debt, price);
        
//         LiquidationHelpers.LiquidationValues memory singleLiquidation = 
//             LiquidationHelpers.calculateLiquidationValuesRecoveryMode(
//                 trove.debt,
//                 trove.coll,
//                 remainingUSDF,
//                 price,
//                 ICR
//             );

//         // Update totals with new liquidation values
//         totals.totalCollInSequence += singleLiquidation.entireTroveColl;
//         totals.totalDebtInSequence += singleLiquidation.entireTroveDebt;
//         totals.totalCollGasCompensation += singleLiquidation.collGasCompensation;
//         totals.totalDebtToOffset += singleLiquidation.debtToOffset;
//         totals.totalCollToSendToSP += singleLiquidation.collToSendToSP;
//         totals.totalDebtToRedistribute += singleLiquidation.debtToRedistribute;
//         totals.totalCollToRedistribute += singleLiquidation.collToRedistribute;
//         totals.totalCollSurplus += singleLiquidation.collSurplus;
        
//         // Close trove or update with surplus
//         if (singleLiquidation.collSurplus > 0) {
//             troves[borrower][asset].coll = singleLiquidation.collSurplus;
//             troves[borrower][asset].debt = trove.debt - singleLiquidation.entireTroveDebt;
//         } else {
//             _closeTrove(borrower, asset);
//         }

//         return remainingUSDF - singleLiquidation.debtToOffset;
//     }

//     function _liquidateNormalMode(
//         IStabilityPool stabilityPoolCached,
//         address asset,
//         address borrower,
//         uint256 remainingUSDF,
//         LiquidationTotals memory totals,
//         uint256 price
//     ) internal returns (uint256) {
//         Trove memory trove = troves[borrower][asset];
        
//         LiquidationHelpers.LiquidationValues memory singleLiquidation = 
//             LiquidationHelpers.calculateLiquidationValuesNormalMode(
//                 trove.debt,
//                 trove.coll,
//                 remainingUSDF,
//                 price
//             );

//         // Update totals with new liquidation values
//         totals.totalCollInSequence += singleLiquidation.entireTroveColl;
//         totals.totalDebtInSequence += singleLiquidation.entireTroveDebt;
//         totals.totalCollGasCompensation += singleLiquidation.collGasCompensation;
//         totals.totalDebtToOffset += singleLiquidation.debtToOffset;
//         totals.totalCollToSendToSP += singleLiquidation.collToSendToSP;
//         totals.totalDebtToRedistribute += singleLiquidation.debtToRedistribute;
//         totals.totalCollToRedistribute += singleLiquidation.collToRedistribute;
//         totals.totalCollSurplus += singleLiquidation.collSurplus;
        
//         _closeTrove(borrower, asset);

//         return remainingUSDF - singleLiquidation.debtToOffset;
//     }

//     function _closeTrove(address borrower, address asset) internal {
//         troves[borrower][asset].status = Status.closedByOwner; // Closed
//         troves[borrower][asset].coll = 0;
//         troves[borrower][asset].debt = 0;
        
//         // Remove from sorted troves
//         sortedTroves.remove(asset, borrower);
        
//         emit TroveClosed(borrower, asset);
//     }

//     function _redistributeDebtAndColl(address asset, uint256 debtToRedistribute, uint256 collToRedistribute) internal {
//         if (totalStakes[asset] == 0) return;
        
//         uint256 collRewardPerUnitStaked = collToRedistribute.mulDiv(DECIMAL_PRECISION, totalStakes[asset]);
//         uint256 debtRewardPerUnitStaked = debtToRedistribute.mulDiv(DECIMAL_PRECISION, totalStakes[asset]);
        
//         L_Collateral[asset] += collRewardPerUnitStaked;
//         L_Debt[asset] += debtRewardPerUnitStaked;
        
//         emit LTermsUpdated(asset, L_Collateral[asset], L_Debt[asset]);
//     }

//     function getEntireSystemColl(address asset) public view returns (uint256) {
//         // This would integrate with ActivePool and DefaultPool
//         return totalCollateralSnapshot[asset]; // Simplified for now
//     }
    
//     function getEntireSystemDebt(address asset) public view returns (uint256) {
//         return totalDebt[asset];
//     }

//     function _applyPendingRewards(address borrower, address asset) internal {
//         if (_hasPendingRewards(borrower, asset)) {
//             Trove storage trove = troves[borrower][asset];
            
//             uint256 pendingCollReward = _getPendingCollateralReward(borrower, asset);
//             uint256 pendingDebtReward = _getPendingDebtReward(borrower, asset);
            
//             trove.coll += pendingCollReward;
//             trove.debt += pendingDebtReward;
            
//             trove.L_CollateralSnapshot = L_Collateral[asset];
//             trove.L_DebtSnapshot = L_Debt[asset];
//         }
//     }

//     function _hasPendingRewards(address borrower, address asset) internal view returns (bool) {
//         Trove storage trove = troves[borrower][asset];
//         return trove.L_CollateralSnapshot < L_Collateral[asset];
//     }

//     function _getPendingCollateralReward(address borrower, address asset) internal view returns (uint256) {
//         Trove storage trove = troves[borrower][asset];
//         uint256 snapshotCollateral = trove.L_CollateralSnapshot;
//         uint256 rewardPerUnitStaked = L_Collateral[asset] - snapshotCollateral;
        
//         if (rewardPerUnitStaked == 0 || trove.stake == 0) return 0;
        
//         return trove.stake.mulDiv(rewardPerUnitStaked, DECIMAL_PRECISION);
//     }

//     function _getPendingDebtReward(address borrower, address asset) internal view returns (uint256) {
//         Trove storage trove = troves[borrower][asset];
//         uint256 snapshotDebt = trove.L_DebtSnapshot;
//         uint256 rewardPerUnitStaked = L_Debt[asset] - snapshotDebt;
        
//         if (rewardPerUnitStaked == 0 || trove.stake == 0) return 0;
        
//         return trove.stake.mulDiv(rewardPerUnitStaked, DECIMAL_PRECISION);
//     }

//     function _computeNewStake(address asset, uint256 coll) internal view returns (uint256) {
//         if (totalCollateral[asset] == 0) return coll;
//         return coll.mulDiv(totalStakes[asset], totalCollateral[asset]);
//     }

//     function _checkRecoveryMode(address asset, uint256 price) internal view returns (bool) {
//         uint256 TCR = _getTCR(asset, price);
//         return TCR < CCR;
//     }

//     function _getTCR(address asset, uint256 price) internal view returns (uint256) {
//         uint256 entireSystemColl = getEntireSystemColl(asset);
//         uint256 entireSystemDebt = getEntireSystemDebt(asset);
        
//         if (entireSystemDebt > 0) {
//             return entireSystemColl.mulDiv(price, entireSystemDebt);
//         }
//         return type(uint256).max;
//     }

//     function getCurrentICR(address borrower, address asset) public view returns (uint256) {
//         Trove storage trove = troves[borrower][asset];
//         if (trove.debt == 0) return type(uint256).max;
        
//         uint256 currentCollateral = trove.coll;
//         uint256 currentDebt = trove.debt;
        
//         // Add pending rewards
//         uint256 pendingCollReward = _getPendingCollateralReward(borrower, asset);
//         uint256 pendingDebtReward = _getPendingDebtReward(borrower, asset);
        
//         currentCollateral += pendingCollReward;
//         currentDebt += pendingDebtReward;
        
//         uint256 price = priceOracle.getPrice(asset);
//         return currentCollateral.mulDiv(price, currentDebt);
//     }

//     function getTroveDebtAndColl(address borrower, address asset) external view returns (uint256 debt, uint256 coll) {
//         Trove storage trove = troves[borrower][asset];
//         debt = trove.debt + _getPendingDebtReward(borrower, asset);
//         coll = trove.coll + _getPendingCollateralReward(borrower, asset);
//     }

//     function getTroveStatus(address borrower, address asset) external view returns (uint256) {
//         return uint256(troves[borrower][asset].status);
//     }

//     /**
//      * @dev Finalize liquidation
//      */
//     function _finalizeLiquidation(
//         IStabilityPool stabilityPoolCached,
//         address asset,
//         LiquidationTotals memory totals,
//         uint256 price
//     ) internal {
//         // Update system snapshots
//         _updateSystemSnapshots_excludeCollRemainder(asset, totals.totalCollToRedistribute);
        
//         // Redistribute debt and collateral
//         if (totals.totalDebtToRedistribute > 0) {
//             _redistributeDebtAndColl(asset, totals.totalDebtToRedistribute, totals.totalCollToRedistribute);
//         }
        
//         // Send collateral to stability pool
//         if (totals.totalCollToSendToSP > 0) {
//             stabilityPoolCached.offset(asset, totals.totalDebtToOffset, totals.totalCollToSendToSP);
//         }
        
//         // Update total debt and collateral
//         totalDebt[asset] -= totals.totalDebtInSequence;
//         totalCollateral[asset] -= totals.totalCollInSequence;
//     }

//     /**
//      * @dev Update system snapshots excluding collateral remainder
//      */
//     function _updateSystemSnapshots_excludeCollRemainder(address asset, uint256 collRemainder) internal {
//         totalStakesSnapshot[asset] = totalStakes[asset];
//         totalCollateralSnapshot[asset] = totalCollateral[asset] - collRemainder;
        
//         emit SystemSnapshotsUpdated(asset, totalStakesSnapshot[asset], totalCollateralSnapshot[asset]);
//     }

//     // Simplified functions for compilation
//     function liquidateTroves(address asset, uint256 n) external nonReentrant {
//         require(n > 0, "Must liquidate at least one trove");
//         emit TroveLiquidated(address(0), asset, 0, 0, TroveManagerOperation.liquidateInNormalMode);
//     }

//     function redeemCollateral(
//         address asset,
//         uint256 usdfAmount,
//         address firstRedemptionHint,
//         address upperPartialRedemptionHint,
//         address lowerPartialRedemptionHint,
//         uint256 partialRedemptionHintNICR,
//         uint256 maxIterations,
//         uint256 maxFeePercentage
//     ) external nonReentrant {
//         require(usdfAmount > 0, "Amount must be greater than zero");
//         require(usdfToken.balanceOf(msg.sender) >= usdfAmount, "Insufficient USDF balance");
        
//         // Simplified redemption logic
//         usdfToken.burnFrom(msg.sender, usdfAmount);
//         emit Redemption(msg.sender, usdfAmount, 0, 0);
//     }
// }
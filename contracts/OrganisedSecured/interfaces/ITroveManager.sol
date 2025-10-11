// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ITroveManager
 * @notice Interface for gas-optimized Trove liquidation and management
 * @dev Handles liquidations, redemptions, and trove status queries
 */
interface ITroveManager {

    // ============ Enums ============

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    // ============ Events ============

    event TroveLiquidated(
        address indexed borrower,
        address indexed asset,
        uint256 debt,
        uint256 collateral,
        uint8 operation
    );

    event TroveUpdated(
        address indexed borrower,
        address indexed asset,
        uint256 debt,
        uint256 collateral,
        uint256 stake,
        uint8 operation
    );

    event Liquidation(
        address indexed asset,
        uint256 liquidatedDebt,
        uint256 liquidatedColl,
        uint256 collGasCompensation,
        uint256 USDFGasCompensation
    );

    event Redemption(
        address indexed asset,
        uint256 attemptedUSDF,
        uint256 actualUSDF,
        uint256 collSent,
        uint256 collFee
    );

    event SystemSnapshotsUpdated(
        address indexed asset,
        uint256 totalStakes,
        uint256 totalCollateral
    );

    event LTermsUpdated(
        address indexed asset,
        uint256 L_Collateral,
        uint256 L_Debt
    );

    event TroveSnapshotsUpdated(
        address indexed asset,
        uint256 L_Collateral,
        uint256 L_Debt
    );

    event BaseRateUpdated(uint256 baseRate);
    event LastFeeOpTimeUpdated(uint256 lastFeeOpTime);
    event TotalStakesUpdated(address indexed asset, uint256 newTotalStakes);
    event SystemDebtRedistributionIndexUpdated(address indexed asset, uint256 systemDebtRedistributionIndex);

    // ============ Custom Errors ============

    error TroveNotActive(address borrower, address asset);
    error TroveNotExists(address borrower, address asset);
    error NothingToLiquidate();
    error InsufficientCollateralRatio(uint256 icr, uint256 mcr);
    error InvalidAsset(address asset);
    error InvalidAmount(uint256 amount);
    error BorrowerOperationsOnly();
    error StabilityPoolOnly();
    error ArrayLengthMismatch();
    error NoTrovesToLiquidate();
    error EmptyArray();

    // ============ Liquidation Functions ============

    /**
     * @notice Liquidate a single undercollateralized trove
     * @param borrower Address of borrower to liquidate
     * @param asset Collateral asset address
     * @dev Requires ICR < MCR (110%)
     * @dev Gas target: <120k
     */
    function liquidate(address borrower, address asset) external;

    /**
     * @notice Liquidate multiple troves in a single transaction
     * @param asset Collateral asset address
     * @param borrowers Array of borrower addresses to liquidate
     * @param maxIterations Maximum number of troves to liquidate
     * @dev Continues until maxIterations reached or all undercollateralized troves liquidated
     * @dev Gas target: <80k per trove after first
     */
    function batchLiquidateTroves(
        address asset,
        address[] calldata borrowers,
        uint256 maxIterations
    ) external;

    /**
     * @notice Liquidate troves sequentially starting from lowest ICR
     * @param asset Collateral asset address
     * @param n Number of troves to attempt
     */
    function liquidateTroves(address asset, uint256 n) external;

    // ============ Redemption Functions ============

    /**
     * @notice Redeem USDF for collateral at face value
     * @param asset Collateral asset to receive
     * @param USDBAmount Amount of USDF to redeem
     * @param firstRedemptionHint Hint for starting trove
     * @param upperPartialRedemptionHint Upper hint for partial redemption
     * @param lowerPartialRedemptionHint Lower hint for partial redemption
     * @param partialRedemptionHintNICR NICR of hinted trove
     * @param maxIterations Maximum troves to redeem from
     * @param maxFeePercentage Maximum acceptable fee percentage
     */
    function redeemCollateral(
        address asset,
        uint256 USDBAmount,
        address firstRedemptionHint,
        address upperPartialRedemptionHint,
        address lowerPartialRedemptionHint,
        uint256 partialRedemptionHintNICR,
        uint256 maxIterations,
        uint256 maxFeePercentage
    ) external;

    // ============ Trove Management (BorrowerOperations Only) ============

    /**
     * @notice Update trove data (called by BorrowerOperations)
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @param debt New debt amount
     * @param collateral New collateral amount
     * @param isDebtIncrease Whether debt increased
     */
    function updateTrove(
        address borrower,
        address asset,
        uint256 debt,
        uint256 collateral,
        bool isDebtIncrease
    ) external;

    /**
     * @notice Remove trove stake (called by BorrowerOperations)
     * @param borrower Borrower address
     * @param asset Collateral asset
     */
    function removeStake(address borrower, address asset) external;

    /**
     * @notice Close trove (called by BorrowerOperations)
     * @param borrower Borrower address
     * @param asset Collateral asset
     */
    function closeTrove(address borrower, address asset) external;

    // ============ View Functions ============

    /**
     * @notice Get trove status
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return Trove status enum
     */
    function getTroveStatus(address borrower, address asset) external view returns (Status);

    /**
     * @notice Get trove debt and collateral
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return debt Total debt including pending rewards
     * @return collateral Total collateral including pending rewards
     */
    function getTroveDebtAndColl(
        address borrower,
        address asset
    ) external view returns (uint256 debt, uint256 collateral);

    /**
     * @notice Get pending collateral reward for trove
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return Pending collateral reward
     */
    function getPendingCollateralReward(
        address borrower,
        address asset
    ) external view returns (uint256);

    /**
     * @notice Get pending debt reward for trove
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return Pending debt reward
     */
    function getPendingDebtReward(
        address borrower,
        address asset
    ) external view returns (uint256);

    /**
     * @notice Check if trove has pending rewards
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return True if trove has pending rewards
     */
    function hasPendingRewards(address borrower, address asset) external view returns (bool);

    /**
     * @notice Get entire debt and collateral including pending rewards
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return debt Total debt including pending rewards
     * @return collateral Total collateral including pending rewards
     * @return pendingUSDBDebtReward Pending debt reward
     * @return pendingCollateralReward Pending collateral reward
     */
    function getEntireDebtAndColl(
        address borrower,
        address asset
    ) external view returns (
        uint256 debt,
        uint256 collateral,
        uint256 pendingUSDBDebtReward,
        uint256 pendingCollateralReward
    );

    /**
     * @notice Get current Individual Collateral Ratio
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return ICR in 1e18 precision (e.g., 1.5e18 = 150%)
     */
    function getCurrentICR(
        address borrower,
        address asset
    ) external view returns (uint256);

    /**
     * @notice Get nominal ICR (collateral * NICR_PRECISION / debt)
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return NICR in 1e20 precision
     */
    function getNominalICR(address borrower, address asset) external view returns (uint256);

    /**
     * @notice Check if system is in recovery mode
     * @param asset Collateral asset
     * @return True if TCR < CCR (150%)
     */
    function checkRecoveryMode(address asset) external view returns (bool);

    /**
     * @notice Get Total Collateral Ratio for entire system
     * @param asset Collateral asset
     * @return TCR in 1e18 precision
     */
    function getTCR(address asset) external view returns (uint256);

    /**
     * @notice Get entire system collateral and debt
     * @param asset Collateral asset
     * @return totalColl Total collateral in system
     * @return totalDebt Total debt in system
     */
    function getEntireSystemColl(address asset) external view returns (uint256 totalColl, uint256 totalDebt);

    /**
     * @notice Get total stakes for an asset
     * @param asset Collateral asset
     * @return Total stakes
     */
    function totalStakes(address asset) external view returns (uint256);

    /**
     * @notice Get total collateral snapshot for an asset
     * @param asset Collateral asset
     * @return Total collateral snapshot
     */
    function totalStakesSnapshot(address asset) external view returns (uint256);

    /**
     * @notice Get total collateral for an asset
     * @param asset Collateral asset
     * @return Total collateral
     */
    function totalCollateralSnapshot(address asset) external view returns (uint256);

    /**
     * @notice Get L_Collateral term for redistribution
     * @param asset Collateral asset
     * @return L_Collateral value
     */
    function L_Collateral(address asset) external view returns (uint256);

    /**
     * @notice Get L_Debt term for redistribution
     * @param asset Collateral asset
     * @return L_Debt value
     */
    function L_Debt(address asset) external view returns (uint256);

    /**
     * @notice Get redemption rate
     * @return Current redemption rate
     */
    function getRedemptionRate() external view returns (uint256);

    /**
     * @notice Get redemption rate with decay
     * @return Redemption rate with decay applied
     */
    function getRedemptionRateWithDecay() external view returns (uint256);

    /**
     * @notice Get redemption fee for a given collateral amount
     * @param collateralDrawn Amount of collateral
     * @return Redemption fee
     */
    function getRedemptionFeeWithDecay(uint256 collateralDrawn) external view returns (uint256);

    /**
     * @notice Get base rate
     * @return Current base rate
     */
    function baseRate() external view returns (uint256);
}

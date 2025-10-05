// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IBorrowerOperations
 * @notice Interface for gas-optimized borrower operations
 * @dev Main user interface for CDP (Trove) management
 */
interface IBorrowerOperations {

    // ============ Events ============

    event TroveUpdated(
        address indexed borrower,
        address indexed asset,
        uint256 debt,
        uint256 coll,
        uint256 stake,
        uint8 operation
    );

    event TroveClosed(
        address indexed borrower,
        address indexed asset
    );

    event BorrowingFeePaid(
        address indexed borrower,
        address indexed asset,
        uint256 feeAmount
    );

    // ============ Errors ============

    error TroveAlreadyExists(address borrower, address asset);
    error TroveNotActive(address borrower, address asset);
    error InsufficientCollateralRatio(uint256 icr, uint256 required);
    error InvalidMaxFeePercentage(uint256 maxFee);
    error FeeExceedsMaximum(uint256 fee, uint256 maxFee);
    error InvalidAmount(uint256 amount);
    error DebtBelowMinimum(uint256 debt, uint256 minimum);
    error InvalidAsset(address asset);

    // ============ Structs ============

    struct TroveChange {
        uint256 collateralChange;
        uint256 debtChange;
        bool isCollateralIncrease;
        bool isDebtIncrease;
    }

    // ============ Core Functions ============

    /**
     * @notice Open a new trove (CDP)
     * @param asset Collateral asset address
     * @param maxFeePercentage Maximum borrowing fee (in basis points, 10000 = 100%)
     * @param collateralAmount Amount of collateral to deposit
     * @param usdfAmount Amount of USDF to borrow
     * @param upperHint Address hint for sorted list insertion
     * @param lowerHint Address hint for sorted list insertion
     */
    function openTrove(
        address asset,
        uint256 maxFeePercentage,
        uint256 collateralAmount,
        uint256 usdfAmount,
        address upperHint,
        address lowerHint
    ) external payable;

    /**
     * @notice Close trove and repay all debt
     * @param asset Collateral asset address
     */
    function closeTrove(address asset) external;

    /**
     * @notice Adjust trove collateral and/or debt
     * @param asset Collateral asset address
     * @param maxFeePercentage Maximum borrowing fee if increasing debt
     * @param collateralChange Amount of collateral to add/remove
     * @param debtChange Amount of debt to borrow/repay
     * @param isCollateralIncrease True to add, false to remove
     * @param isDebtIncrease True to borrow more, false to repay
     * @param upperHint Address hint for sorted list
     * @param lowerHint Address hint for sorted list
     */
    function adjustTrove(
        address asset,
        uint256 maxFeePercentage,
        uint256 collateralChange,
        uint256 debtChange,
        bool isCollateralIncrease,
        bool isDebtIncrease,
        address upperHint,
        address lowerHint
    ) external payable;

    /**
     * @notice Claim surplus collateral after liquidation
     * @param asset Collateral asset address
     */
    function claimCollateral(address asset) external;

    // ============ View Functions ============

    /**
     * @notice Get trove debt and collateral
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return debt Total debt including pending interest
     * @return coll Collateral amount
     */
    function getEntireDebtAndColl(
        address borrower,
        address asset
    ) external view returns (uint256 debt, uint256 coll);

    /**
     * @notice Calculate current borrowing fee
     * @param asset Collateral asset
     * @param usdfAmount Amount of USDF to borrow
     * @return fee Borrowing fee amount
     */
    function getBorrowingFee(
        address asset,
        uint256 usdfAmount
    ) external view returns (uint256 fee);

    /**
     * @notice Get borrowing fee rate
     * @param asset Collateral asset
     * @return rate Borrowing fee rate in basis points
     */
    function getBorrowingFeeRate(address asset) external view returns (uint256 rate);

    /**
     * @notice Check if trove is active
     * @param borrower Borrower address
     * @param asset Collateral asset
     * @return active True if trove exists and is active
     */
    function isTroveActive(address borrower, address asset) external view returns (bool active);
}

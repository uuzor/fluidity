// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITroveManager {
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    enum TroveManagerOperation {
        applyPendingRewards,
        liquidateInNormalMode,
        liquidateInRecoveryMode,
        redeemCollateral,
        updateTrove
    }

    struct Trove {
        uint256 debt;
        uint256 coll;
        uint256 stake;
        Status status;
        uint128 arrayIndex;
        uint256 L_CollateralSnapshot;
        uint256 L_DebtSnapshot;
    }

    // Events
    event TroveUpdated(address indexed borrower, address indexed asset, uint256 debt, uint256 coll, uint256 stake, TroveManagerOperation operation);
    event TroveLiquidated(address indexed borrower, address indexed asset, uint256 debt, uint256 coll, TroveManagerOperation operation);
    event Redemption(address indexed redeemer, uint256 usdfAmount, uint256 collAmount, uint256 fee);

    // Trove management
    function updateTrove(address borrower, address asset, uint256 collChange, bool isCollIncrease, uint256 debtChange, bool isDebtIncrease) external returns (uint256, uint256);
    function liquidate(address borrower, address asset) external;
    function liquidateTroves(address asset, uint256 n) external;
    function redeemCollateral(address asset, uint256 usdfAmount, address firstRedemptionHint, address upperPartialRedemptionHint, address lowerPartialRedemptionHint, uint256 partialRedemptionHintNICR, uint256 maxIterations, uint256 maxFeePercentage) external;

    // View functions
    function getCurrentICR(address borrower, address asset) external view returns (uint256);
    function getTroveDebtAndColl(address borrower, address asset) external view returns (uint256 debt, uint256 coll);
    function getTroveStatus(address borrower, address asset) external view returns (uint256);
    function totalStakes(address asset) external view returns (uint256);
    function totalCollateral(address asset) external view returns (uint256);
    function totalDebt(address asset) external view returns (uint256);
}
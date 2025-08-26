// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBorrowerOperations {
    enum BorrowerOperation {
        openTrove,
        closeTrove,
        adjustTrove,
        addColl,
        withdrawColl,
        withdrawUSDF,
        repayUSDF
    }

    // Events
    event TroveUpdated(address indexed borrower, address indexed asset, uint256 debt, uint256 coll, BorrowerOperation operation);

    // Trove operations
    function openTrove(address asset, uint256 maxFeePercentage, uint256 collAmount, uint256 usdfAmount, address upperHint, address lowerHint) external payable;
    function addColl(address asset, uint256 collAmount, address upperHint, address lowerHint) external payable;
    function withdrawColl(address asset, uint256 collAmount, address upperHint, address lowerHint) external;
    function withdrawUSDF(address asset, uint256 maxFeePercentage, uint256 usdfAmount, address upperHint, address lowerHint) external;
    function repayUSDF(address asset, uint256 usdfAmount, address upperHint, address lowerHint) external;
    function adjustTrove(address asset, uint256 maxFeePercentage, uint256 collWithdrawal, uint256 usdfChange, bool isDebtIncrease, address upperHint, address lowerHint) external payable;
    function closeTrove(address asset) external;

    // View functions
    function getCompositeDebt(address asset, uint256 debt) external view returns (uint256);
    function getBorrowingFee(address asset, uint256 usdfDebt) external view returns (uint256);
    function getBorrowingFeeWithDecay(address asset, uint256 usdfDebt) external view returns (uint256);
}
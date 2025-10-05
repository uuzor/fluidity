// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStabilityPool {
    // Events
    event StabilityPoolUSDF(uint256 newTotalUSDF);
    event StabilityPoolCollateral(address indexed asset, uint256 newTotalCollateral);
    event UserDepositChanged(address indexed depositor, uint256 newDeposit);
    event CollateralGainWithdrawn(address indexed depositor, address indexed asset, uint256 amount);
    event FLUIDPaidToDepositor(address indexed depositor, uint256 amount);

    // User operations
    function provideToSP(uint256 amount, address frontEndTag) external;
    function withdrawFromSP(uint256 amount) external;
    function withdrawAllFromSP() external;

    // Liquidation operations
    function offset(address asset, uint256 debtToOffset, uint256 collToAdd) external;

    // View functions
    function getTotalUSDF() external view returns (uint256);
    function getTotalCollateral(address asset) external view returns (uint256);
    function getCompoundedUSDF(address depositor) external view returns (uint256);
    function getDepositorCollateralGain(address depositor, address asset) external view returns (uint256);
    function getDepositorFLUIDGain(address depositor) external view returns (uint256);
}
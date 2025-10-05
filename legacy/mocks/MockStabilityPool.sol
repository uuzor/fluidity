// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockStabilityPool {
    uint256 public totalUSDFDeposits = 1000000e18; // 1M USDF available for liquidations
    
    constructor() {}
    
    function provideToSP(uint256 _amount, address _frontEndTag) external {}
    function withdrawFromSP(uint256 _amount) external {}
    function withdrawETHGainToTrove(address _upperHint, address _lowerHint) external {}
    function getCompoundedUSDFDeposit(address _depositor) external view returns (uint256) {
        return 0;
    }
    function getDepositorETHGain(address _depositor) external view returns (uint256) {
        return 0;
    }
    
    // Functions needed by TroveManager liquidation logic
    function getTotalUSDF() external view returns (uint256) {
        return totalUSDFDeposits;
    }
    
    function offset(address asset, uint256 debtToOffset, uint256 collToSendToSP) external {
        // Mock implementation - just record the offset operation
        // In real implementation, this would handle the debt offset and collateral distribution
        if (debtToOffset <= totalUSDFDeposits) {
            totalUSDFDeposits -= debtToOffset;
        }
    }
}
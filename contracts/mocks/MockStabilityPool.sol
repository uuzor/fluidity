// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockStabilityPool {
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
}
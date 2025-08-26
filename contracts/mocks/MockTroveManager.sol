// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockTroveManager {
    mapping(address => mapping(address => uint256)) public troveStatus; // borrower => asset => status
    mapping(address => mapping(address => uint256)) public troveDebt;   // borrower => asset => debt
    mapping(address => mapping(address => uint256)) public troveColl;   // borrower => asset => collateral
    
    constructor() {}
    
    function getTroveOwnersCount() external view returns (uint256) {
        return 0;
    }
    
    function getTroveFromTroveOwnersArray(uint256 /* _index */) external view returns (address) {
        return address(0);
    }
    
    function getCurrentICR(address /* _borrower */, address /* _asset */, uint256 /* _price */) external view returns (uint256) {
        return 0;
    }
    
    function getTroveStatus(address _borrower, address _asset) external view returns (uint256) {
        return troveStatus[_borrower][_asset];
    }
    
    function updateTrove(
        address _borrower,
        address _asset,
        uint256 _collAmount,
        bool _isCollIncrease,
        uint256 _debtAmount,
        bool _isDebtIncrease
    ) external returns (uint256 debt, uint256 coll) {
        // Update trove status to active (1) when opening
        if (troveStatus[_borrower][_asset] == 0) {
            troveStatus[_borrower][_asset] = 1;
        }
        
        // Update debt
        if (_isDebtIncrease) {
            troveDebt[_borrower][_asset] += _debtAmount;
        } else {
            troveDebt[_borrower][_asset] = troveDebt[_borrower][_asset] > _debtAmount ? 
                troveDebt[_borrower][_asset] - _debtAmount : 0;
        }
        
        // Update collateral
        if (_isCollIncrease) {
            troveColl[_borrower][_asset] += _collAmount;
        } else {
            troveColl[_borrower][_asset] = troveColl[_borrower][_asset] > _collAmount ? 
                troveColl[_borrower][_asset] - _collAmount : 0;
        }
        
        debt = troveDebt[_borrower][_asset];
        coll = troveColl[_borrower][_asset];
    }
    
    function getTroveDebtAndColl(address _borrower, address _asset) external view returns (uint256 debt, uint256 coll) {
        debt = troveDebt[_borrower][_asset];
        coll = troveColl[_borrower][_asset];
    }
    
    function liquidate(address /* _borrower */, address /* _asset */) external {}
    function liquidateTroves(address /* _asset */, uint256 /* _n */) external {}
    function batchLiquidateTroves(address /* _asset */, address[] calldata /* _troveArray */) external {}
    function redeemCollateral(address /* _asset */, uint256 /* _USDFAmount */, address /* _firstRedemptionHint */, address /* _upperPartialRedemptionHint */, address /* _lowerPartialRedemptionHint */, uint256 /* _partialRedemptionHintNICR */, uint256 /* _maxIterations */, uint256 /* _maxFeePercentage */) external {}
}
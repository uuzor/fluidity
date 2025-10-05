
Warning: Source file does not specify required compiler version! Consider adding "pragma solidity ^0.8.24;"
--> contracts/legacy/BorrowerOperations.sol


Warning: Source file does not specify required compiler version! Consider adding "pragma solidity ^0.8.24;"
--> contracts/legacy/EnhancedStabilityPool.sol


Warning: Source file does not specify required compiler version! Consider adding "pragma solidity ^0.8.24;"
--> contracts/legacy/TroveManager.sol


Warning: This declaration shadows an existing declaration.
  --> contracts/core/LiquidationHelpers.sol:99:13:
   |
99 |             LiquidationValues memory singleLiquidation;
   |             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: The shadowed declaration is here:
  --> contracts/core/LiquidationHelpers.sol:92:30:
   |
92 |     ) external pure returns (LiquidationValues memory singleLiquidation) {
   |                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


TypeError: Contract "UpgradeableBorrowerOperations" should be marked as abstract.
  --> contracts/proxy/UpgradeableBorrowerOperations.sol:19:1:
   |
19 | contract UpgradeableBorrowerOperations is
   | ^ (Relevant source part starts here and spans across multiple lines).
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:20:5:
   |
20 |     function addColl(address asset, uint256 collAmount, address upperHint, address lowerHint) external payable;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:24:5:
   |
24 |     function adjustTrove(address asset, ... ddress lowerHint) external payable;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:29:5:
   |
29 |     function getBorrowingFee(address asset, uint256 usdfDebt) external view returns (uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:30:5:
   |
30 |     function getBorrowingFeeWithDecay(address asset, uint256 usdfDebt) external view returns (uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:28:5:
   |
28 |     function getCompositeDebt(address asset, uint256 debt) external view returns (uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:23:5:
   |
23 |     function repayUSDF(address asset, uint256 usdfAmount, address upperHint, address lowerHint) external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:21:5:
   |
21 |     function withdrawColl(address asset, uint256 collAmount, address upperHint, address lowerHint) external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IBorrowerOperations.sol:22:5:
   |
22 |     function withdrawUSDF(address asset, uint256 maxFeePercentage, uint256 usdfAmount, address upperHint, address lowerHint) external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


DeclarationError: Event with same name and parameter types defined twice.
  --> contracts/proxy/UpgradeableStabilityPool.sol:78:5:
   |
78 |     event CollateralGainWithdrawn(address indexed depositor, address indexed asset, uint256 amount);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Other declaration is here:
 --> contracts/interfaces/IStabilityPool.sol:9:5:
  |
9 |     event CollateralGainWithdrawn(address indexed depositor, address indexed asset, uint256 amount);
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


TypeError: Function has override specified but does not override anything.
   --> contracts/proxy/UpgradeableStabilityPool.sol:223:9:
    |
223 |         override
    |         ^^^^^^^^


TypeError: Function has override specified but does not override anything.
   --> contracts/proxy/UpgradeableStabilityPool.sol:264:9:
    |
264 |         override
    |         ^^^^^^^^


TypeError: Contract "UpgradeableStabilityPool" should be marked as abstract.
  --> contracts/proxy/UpgradeableStabilityPool.sol:19:1:
   |
19 | contract UpgradeableStabilityPool is
   | ^ (Relevant source part starts here and spans across multiple lines).
Note: Missing implementation:
  --> contracts/interfaces/IStabilityPool.sol:23:5:
   |
23 |     function getCompoundedUSDF(address depositor) external view returns (uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IStabilityPool.sol:25:5:
   |
25 |     function getDepositorFLUIDGain(address depositor) external view returns (uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IStabilityPool.sol:18:5:
   |
18 |     function offset(address asset, uint256 debtToOffset, uint256 collToAdd) external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/IStabilityPool.sol:15:5:
   |
15 |     function withdrawAllFromSP() external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


TypeError: Overriding function return types differ.
   --> contracts/proxy/UpgradeableTroveManager.sol:168:5:
    |
168 |     function updateTrove(
    |     ^ (Relevant source part starts here and spans across multiple lines).
Note: Overridden function is here:
  --> contracts/interfaces/ITroveManager.sol:37:5:
   |
37 |     function updateTrove(address borrow ... xternal returns (uint256, uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


TypeError: Overriding function return types differ.
   --> contracts/proxy/UpgradeableTroveManager.sol:225:5:
    |
225 |     function liquidate(address borrower, address asset)
    |     ^ (Relevant source part starts here and spans across multiple lines).
Note: Overridden function is here:
  --> contracts/interfaces/ITroveManager.sol:38:5:
   |
38 |     function liquidate(address borrower, address asset) external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


TypeError: Contract "UpgradeableTroveManager" should be marked as abstract.
  --> contracts/proxy/UpgradeableTroveManager.sol:20:1:
   |
20 | contract UpgradeableTroveManager is
   | ^ (Relevant source part starts here and spans across multiple lines).
Note: Missing implementation:
  --> contracts/interfaces/ITroveManager.sol:43:5:
   |
43 |     function getCurrentICR(address borrower, address asset) external view returns (uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/ITroveManager.sol:44:5:
   |
44 |     function getTroveDebtAndColl(address borrower, address asset) external view returns (uint256 debt, uint256 coll);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/ITroveManager.sol:45:5:
   |
45 |     function getTroveStatus(address borrower, address asset) external view returns (uint256);
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/ITroveManager.sol:39:5:
   |
39 |     function liquidateTroves(address asset, uint256 n) external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Note: Missing implementation:
  --> contracts/interfaces/ITroveManager.sol:40:5:
   |
40 |     function redeemCollateral(address a ... uint256 maxFeePercentage) external;
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


TypeError: Member "getTroveData" not found or not visible after argument-dependent lookup in contract ITroveManager.
   --> contracts/proxy/UpgradeableBorrowerOperations.sol:193:13:
    |
193 |             troveManager.getTroveData(msg.sender, asset);
    |             ^^^^^^^^^^^^^^^^^^^^^^^^^


Error HH600: Compilation failed

For more info go to https://hardhat.org/HH600 or run Hardhat with --show-stack-traces
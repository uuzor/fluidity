// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import "../interfaces/IBorrowerOperations.sol";
// import "../interfaces/ITroveManager.sol";
// import "../tokens/USDF.sol";
// import "../libraries/Math.sol";
// import "./PriceOracle.sol";

// /**
//  * @title BorrowerOperations
//  * @dev Interface for users to manage their troves - SECURITY HARDENED
//  */
// contract BorrowerOperations is IBorrowerOperations, Ownable, ReentrancyGuard {
//     using SafeERC20 for IERC20;
//     using Math for uint256;

//     // Constants
//     uint256 public constant DECIMAL_PRECISION = 1e18;
//     uint256 public constant MIN_COLLATERAL_RATIO = 1.35e18; // 135%
//     uint256 public constant BORROWING_FEE_FLOOR = 0.005e18; // 0.5%
//     uint256 public constant MAX_BORROWING_FEE = 0.05e18; // 5%
//     uint256 public constant MIN_NET_DEBT = 200e18; // 200 USDF minimum

//     // State variables
//     ITroveManager public troveManager;
//     USDF public usdfToken;
//     PriceOracle public priceOracle;
//     address public activePool;
//     address public defaultPool;
//     address public stabilityPool;
//     address public gasPool;
//     address public collSurplusPool;
//     address public sortedTroves;

//     // Fee tracking
//     mapping(address => uint256) public baseRate; // asset => base rate
    
//     // Security constants
//     uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour max price age
//     uint256 public constant MAX_TROVES_PER_USER = 10;
    
//     // User trove tracking
//     mapping(address => uint256) public userTroveCount;

//     modifier onlyValidAsset(address asset) {
//         require(asset != address(0), "Invalid asset");
//         _;
//     }

//     constructor() Ownable(msg.sender) {}

//     function initialize(
//         address _troveManager,
//         address _usdfToken,
//         address _priceOracle,
//         address _activePool,
//         address _defaultPool,
//         address _stabilityPool,
//         address _gasPool,
//         address _collSurplusPool,
//         address _sortedTroves
//     ) external onlyOwner {
//         require(_priceOracle != address(0), "Invalid price oracle");
//         troveManager = ITroveManager(_troveManager);
//         usdfToken = USDF(_usdfToken);
//         priceOracle = PriceOracle(_priceOracle);
//         activePool = _activePool;
//         defaultPool = _defaultPool;
//         stabilityPool = _stabilityPool;
//         gasPool = _gasPool;
//         collSurplusPool = _collSurplusPool;
//         sortedTroves = _sortedTroves;
//     }

//     /**
//      * @dev Open a new trove
//      */
//     function openTrove(
//         address asset,
//         uint256 maxFeePercentage,
//         uint256 collAmount,
//         uint256 usdfAmount,
//         address upperHint,
//         address lowerHint
//     ) external payable nonReentrant onlyValidAsset(asset) {
//         require(usdfAmount >= MIN_NET_DEBT, "Net debt too small");
//         require(troveManager.getTroveStatus(msg.sender, asset) == 0, "Trove already exists");
//         require(userTroveCount[msg.sender] < MAX_TROVES_PER_USER, "Too many troves per user");
        
//         // Validate price freshness
//         _requireFreshPrice(asset);

//         // Calculate borrowing fee
//         uint256 borrowingFee = _getBorrowingFee(asset, usdfAmount);
//         require(borrowingFee <= usdfAmount.mulDiv(maxFeePercentage, DECIMAL_PRECISION), "Fee exceeds maximum");

//         uint256 netDebt = usdfAmount + borrowingFee;
//         uint256 compositeDebt = netDebt + 200e18; // Gas compensation

//         // Check ICR
//         uint256 ICR = _getICR(asset, collAmount, compositeDebt);
//         require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");

//         // Transfer collateral
//         if (asset == address(0)) {
//             require(msg.value == collAmount, "Incorrect ETH amount");
//         } else {
//             IERC20(asset).safeTransferFrom(msg.sender, address(this), collAmount);
//         }

//         // Update trove
//         (uint256 debt, uint256 coll) = troveManager.updateTrove(
//             msg.sender,
//             asset,
//             collAmount,
//             true, // isCollIncrease
//             compositeDebt,
//             true  // isDebtIncrease
//         );

//         // Mint USDF to user
//         usdfToken.mint(msg.sender, usdfAmount);

//         // Send borrowing fee to fee recipient
//         if (borrowingFee > 0) {
//             usdfToken.mint(owner(), borrowingFee);
//         }

//         // Send gas compensation to gas pool
//         usdfToken.mint(gasPool, 200e18);
        
//         // Increment user trove count
//         userTroveCount[msg.sender]++;

//         emit TroveUpdated(msg.sender, asset, debt, coll, BorrowerOperation.openTrove);
//     }

//     /**
//      * @dev Add collateral to existing trove
//      */
//     function addColl(
//         address asset,
//         uint256 collAmount,
//         address upperHint,
//         address lowerHint
//     ) external payable nonReentrant onlyValidAsset(asset) {
//         require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
//         require(collAmount > 0, "Amount must be greater than 0");

//         // Transfer collateral
//         if (asset == address(0)) {
//             require(msg.value == collAmount, "Incorrect ETH amount");
//         } else {
//             IERC20(asset).safeTransferFrom(msg.sender, address(this), collAmount);
//         }

//         // Update trove
//         (uint256 debt, uint256 coll) = troveManager.updateTrove(
//             msg.sender,
//             asset,
//             collAmount,
//             true, // isCollIncrease
//             0,
//             false // isDebtIncrease
//         );

//         emit TroveUpdated(msg.sender, asset, debt, coll, BorrowerOperation.addColl);
//     }

//     /**
//      * @dev Withdraw collateral from trove
//      */
//     function withdrawColl(
//         address asset,
//         uint256 collAmount,
//         address upperHint,
//         address lowerHint
//     ) external nonReentrant onlyValidAsset(asset) {
//         require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
//         require(collAmount > 0, "Amount must be greater than 0");

//         // Update trove
//         (uint256 debt, uint256 coll) = troveManager.updateTrove(
//             msg.sender,
//             asset,
//             collAmount,
//             false, // isCollIncrease
//             0,
//             false  // isDebtIncrease
//         );

//         // Check ICR after withdrawal
//         uint256 ICR = _getICR(asset, coll, debt);
//         require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");

//         // Transfer collateral to user
//         if (asset == address(0)) {
//             payable(msg.sender).transfer(collAmount);
//         } else {
//             IERC20(asset).safeTransfer(msg.sender, collAmount);
//         }

//         emit TroveUpdated(msg.sender, asset, debt, coll, BorrowerOperation.withdrawColl);
//     }

//     /**
//      * @dev Borrow more USDF
//      */
//     function withdrawUSDF(
//         address asset,
//         uint256 maxFeePercentage,
//         uint256 usdfAmount,
//         address upperHint,
//         address lowerHint
//     ) external nonReentrant onlyValidAsset(asset) {
//         require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
//         require(usdfAmount > 0, "Amount must be greater than 0");

//         // Calculate borrowing fee
//         uint256 borrowingFee = _getBorrowingFee(asset, usdfAmount);
//         require(borrowingFee <= usdfAmount.mulDiv(maxFeePercentage, DECIMAL_PRECISION), "Fee exceeds maximum");

//         uint256 netDebt = usdfAmount + borrowingFee;

//         // Update trove
//         (uint256 debt, uint256 coll) = troveManager.updateTrove(
//             msg.sender,
//             asset,
//             0,
//             false, // isCollIncrease
//             netDebt,
//             true   // isDebtIncrease
//         );

//         // Check ICR after borrowing
//         uint256 ICR = _getICR(asset, coll, debt);
//         require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");

//         // Mint USDF to user
//         usdfToken.mint(msg.sender, usdfAmount);

//         // Send borrowing fee to fee recipient
//         if (borrowingFee > 0) {
//             usdfToken.mint(owner(), borrowingFee);
//         }

//         emit TroveUpdated(msg.sender, asset, debt, coll, BorrowerOperation.withdrawUSDF);
//     }

//     /**
//      * @dev Repay USDF debt
//      */
//     function repayUSDF(
//         address asset,
//         uint256 usdfAmount,
//         address upperHint,
//         address lowerHint
//     ) external nonReentrant onlyValidAsset(asset) {
//         require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
//         require(usdfAmount > 0, "Amount must be greater than 0");
//         require(usdfToken.balanceOf(msg.sender) >= usdfAmount, "Insufficient USDF balance");

//         // Update trove
//         (uint256 debt, uint256 coll) = troveManager.updateTrove(
//             msg.sender,
//             asset,
//             0,
//             false, // isCollIncrease
//             usdfAmount,
//             false  // isDebtIncrease
//         );

//         // Burn USDF
//         usdfToken.burnFrom(msg.sender, usdfAmount);

//         emit TroveUpdated(msg.sender, asset, debt, coll, BorrowerOperation.repayUSDF);
//     }

//     /**
//      * @dev Adjust trove (add/remove collateral and debt in one transaction)
//      */
//     function adjustTrove(
//         address asset,
//         uint256 maxFeePercentage,
//         uint256 collWithdrawal,
//         uint256 usdfChange,
//         bool isDebtIncrease,
//         address upperHint,
//         address lowerHint
//     ) external payable nonReentrant onlyValidAsset(asset) {
//         require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");

//         uint256 collChange = 0;
//         bool isCollIncrease = false;

//         // Handle collateral changes
//         if (msg.value > 0) {
//             require(asset == address(0), "ETH sent for non-ETH asset");
//             collChange = msg.value;
//             isCollIncrease = true;
//         } else if (collWithdrawal > 0) {
//             collChange = collWithdrawal;
//             isCollIncrease = false;
//         }

//         // Handle debt changes
//         uint256 netDebtChange = 0;
//         if (usdfChange > 0) {
//             if (isDebtIncrease) {
//                 uint256 borrowingFee = _getBorrowingFee(asset, usdfChange);
//                 require(borrowingFee <= usdfChange.mulDiv(maxFeePercentage, DECIMAL_PRECISION), "Fee exceeds maximum");
//                 netDebtChange = usdfChange + borrowingFee;

//                 // Mint USDF to user
//                 usdfToken.mint(msg.sender, usdfChange);

//                 // Send borrowing fee to fee recipient
//                 if (borrowingFee > 0) {
//                     usdfToken.mint(owner(), borrowingFee);
//                 }
//             } else {
//                 netDebtChange = usdfChange;
//                 // Burn USDF
//                 usdfToken.burnFrom(msg.sender, usdfChange);
//             }
//         }

//         // Update trove
//         (uint256 debt, uint256 coll) = troveManager.updateTrove(
//             msg.sender,
//             asset,
//             collChange,
//             isCollIncrease,
//             netDebtChange,
//             isDebtIncrease
//         );

//         // Check ICR after adjustment
//         uint256 ICR = _getICR(asset, coll, debt);
//         require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");

//         // Transfer collateral if withdrawing
//         if (collWithdrawal > 0) {
//             if (asset == address(0)) {
//                 payable(msg.sender).transfer(collWithdrawal);
//             } else {
//                 IERC20(asset).safeTransfer(msg.sender, collWithdrawal);
//             }
//         }

//         emit TroveUpdated(msg.sender, asset, debt, coll, BorrowerOperation.adjustTrove);
//     }

//     /**
//      * @dev Close trove
//      */
//     function closeTrove(address asset) external nonReentrant onlyValidAsset(asset) {
//         require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");

//         (uint256 debt, uint256 coll) = troveManager.getTroveDebtAndColl(msg.sender, asset);
//         require(debt > 200e18, "Cannot close trove with only gas compensation");

//         uint256 netDebt = debt - 200e18; // Subtract gas compensation
//         require(usdfToken.balanceOf(msg.sender) >= netDebt, "Insufficient USDF balance");

//         // Update trove (close it)
//         troveManager.updateTrove(
//             msg.sender,
//             asset,
//             coll,
//             false, // isCollIncrease
//             debt,
//             false  // isDebtIncrease
//         );

//         // Burn USDF
//         usdfToken.burnFrom(msg.sender, netDebt);

//         // Burn gas compensation
//         usdfToken.burnFrom(gasPool, 200e18);

//         // Transfer collateral to user
//         if (asset == address(0)) {
//             payable(msg.sender).transfer(coll);
//         } else {
//             IERC20(asset).safeTransfer(msg.sender, coll);
//         }
        
//         // Decrement user trove count
//         userTroveCount[msg.sender]--;

//         emit TroveUpdated(msg.sender, asset, 0, 0, BorrowerOperation.closeTrove);
//     }

//     // View functions
//     function getCompositeDebt(address asset, uint256 debt) external pure returns (uint256) {
//         return debt + 200e18; // Add gas compensation
//     }

//     function getBorrowingFee(address asset, uint256 usdfDebt) external view returns (uint256) {
//         return _getBorrowingFee(asset, usdfDebt);
//     }

//     function getBorrowingFeeWithDecay(address asset, uint256 usdfDebt) external view returns (uint256) {
//         return _getBorrowingFeeWithDecay(asset, usdfDebt);
//     }

//     // Internal functions
//     function _getBorrowingFee(address asset, uint256 usdfDebt) internal view returns (uint256) {
//         return _getBorrowingFeeWithDecay(asset, usdfDebt);
//     }

//     function _getBorrowingFeeWithDecay(address asset, uint256 usdfDebt) internal view returns (uint256) {
//         uint256 borrowingRate = _getBorrowingRate(asset);
//         return usdfDebt.mulDiv(borrowingRate, DECIMAL_PRECISION);
//     }

//     function _getBorrowingRate(address asset) internal view returns (uint256) {
//         return Math.min(BORROWING_FEE_FLOOR + baseRate[asset], MAX_BORROWING_FEE);
//     }

//     function _getICR(address asset, uint256 coll, uint256 debt) internal view returns (uint256) {
//         if (debt == 0) return type(uint256).max;
//         uint256 price = _getPrice(asset);
//         return coll.mulDiv(price, debt);
//     }

//     function _getPrice(address asset) internal view returns (uint256) {
//         uint256 price = priceOracle.getPrice(asset);
//         require(price > 0, "Invalid price from oracle");
//         return price;
//     }
    
//     function _requireFreshPrice(address asset) internal view {
//         uint256 lastUpdate = priceOracle.getLastUpdateTime(asset);
//         require(block.timestamp - lastUpdate <= MAX_PRICE_AGE, "Price too stale");
//     }

//     // Admin functions
//     function setBaseRate(address asset, uint256 _baseRate) external onlyOwner {
//         baseRate[asset] = _baseRate;
//     }
// }
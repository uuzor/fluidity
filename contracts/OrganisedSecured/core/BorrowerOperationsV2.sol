// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/OptimizedSecurityBase.sol";
import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/ILiquidityCore.sol";
import "../interfaces/ISortedTroves.sol";
import "../interfaces/IUSDF.sol";
import "../interfaces/IPriceOracle.sol";
import "../libraries/TransientStorage.sol";
import "../libraries/GasOptimizedMath.sol";

/**
 * @title BorrowerOperationsV2
 * @notice V2: Properly integrated with TroveManagerV2 for clean separation of concerns
 * @dev User-facing contract that delegates trove state management to TroveManagerV2
 *
 * Architecture Changes from V1:
 * - ❌ REMOVED: Duplicate _packedTroves storage
 * - ✅ ADDED: ITroveManager integration for all state changes
 * - ✅ KEPT: _isTroveActive for gas-efficient local checks
 * - ✅ KEPT: User enumeration (_userTroveAssets)
 * - ✅ Calls TroveManager.updateTrove() for openTrove/adjustTrove
 * - ✅ Calls TroveManager.closeTrove() for closeTrove
 *
 * Responsibilities:
 * 1. User input validation
 * 2. Fee calculations
 * 3. Collateral/USDF transfers
 * 4. SortedTroves management
 * 5. Delegate state to TroveManagerV2
 *
 * Gas Optimizations Retained:
 * 1. ✅ TransientStorage for reentrancy guard (~19,800 gas saved)
 * 2. ✅ Price caching in transient storage (~2,000 gas per reuse)
 * 3. ✅ GasOptimizedMath library (~600 gas per calculation)
 * 4. ✅ Efficient sorted list with hints (~25,000 gas saved)
 * 5. ✅ Local _isTroveActive mapping for cheap reads
 *
 * @custom:security-contact security@fluidprotocol.com
 */
contract BorrowerOperationsV2 is OptimizedSecurityBase, IBorrowerOperations {
    using SafeERC20 for IERC20;
    using TransientStorage for bytes32;
    using GasOptimizedMath for uint256;

    // ============ Constants ============

    /// @notice Minimum Collateral Ratio (110%)
    uint256 public constant MCR = 1_100_000_000_000_000_000; // 110%

    /// @notice Critical Collateral Ratio for recovery mode (150%)
    uint256 public constant CCR = 1_500_000_000_000_000_000; // 150%

    /// @notice Minimum borrowing fee (0.5%)
    uint256 public constant BORROWING_FEE_FLOOR = 5e15;

    /// @notice Maximum borrowing fee (5%)
    uint256 public constant MAX_BORROWING_FEE = 5e16;

    /// @notice Minimum net debt (2000 USDF)
    uint256 public constant MIN_NET_DEBT = 2000e18;

    /// @notice Gas compensation reserved per trove (200 USDF)
    uint256 public constant GAS_COMPENSATION = 200e18;

    /// @notice Decimal precision for calculations
    uint256 private constant DECIMAL_PRECISION = 1e18;

    /// @notice Nominal ICR precision multiplier
    uint256 private constant NICR_PRECISION = 1e20;

    /// @notice Collateral scaling factor
    uint256 private constant COLL_SCALE = 1e10;

    // ============ Immutables ============

    /// @notice Core liquidity management contract
    ILiquidityCore public immutable liquidityCore;

    /// @notice Sorted troves list for efficient liquidations
    ISortedTroves public immutable sortedTroves;

    /// @notice USDF stablecoin contract
    IUSDF public immutable usdfToken;

    /// @notice Price oracle contract
    IPriceOracle public immutable priceOracle;

    // ============ Transient Storage Slots (EIP-1153) ============

    /// @notice Cache slot for ICR calculations
    bytes32 private constant ICR_CACHE_SLOT = keccak256("borrower.icr.cache");

    /// @notice Cache slot for price oracle results
    bytes32 private constant PRICE_CACHE_SLOT = keccak256("borrower.price.cache");

    // ============ State Variables ============

    /// @notice TroveManager - Single source of truth for trove data
    /// @dev V2: Changed from immutable to allow setting after deployment (circular dependency)
    ITroveManager public troveManager;

    /// @notice V2: NO MORE _packedTroves - TroveManager owns that!
    /// @dev Only keep lightweight tracking for gas-efficient reads

    /// @notice Active trove tracking (optimized for gas-efficient reads)
    /// @dev mapping(borrower => mapping(asset => isActive))
    mapping(address => mapping(address => bool)) private _isTroveActive;

    /// @notice Borrowing fee rate per asset (in 1e18 precision, e.g., 5e15 = 0.5%)
    /// @dev mapping(asset => feeRate)
    mapping(address => uint256) public borrowingFeeRate;

    /// @notice User's trove assets enumeration for frontend queries
    /// @dev mapping(borrower => asset[]) - list of all assets user has troves in
    mapping(address => address[]) private _userTroveAssets;

    /// @notice Quick lookup for asset index in user's list
    /// @dev mapping(borrower => mapping(asset => index+1)) - 0 means not in list
    mapping(address => mapping(address => uint256)) private _userAssetIndex;

    // ============ Constructor ============

    /**
     * @notice Initialize BorrowerOperationsV2 with core dependencies
     * @param _accessControl Access control manager address
     * @param _liquidityCore LiquidityCore contract address
     * @param _sortedTroves SortedTroves contract address
     * @param _usdfToken USDF token contract address
     * @param _priceOracle Price oracle contract address
     */
    constructor(
        address _accessControl,
        address _liquidityCore,
        address _sortedTroves,
        address _usdfToken,
        address _priceOracle
    ) OptimizedSecurityBase(_accessControl) {
        require(_liquidityCore != address(0), "BO: Invalid LiquidityCore");
        require(_sortedTroves != address(0), "BO: Invalid SortedTroves");
        require(_usdfToken != address(0), "BO: Invalid USDF");
        require(_priceOracle != address(0), "BO: Invalid PriceOracle");

        // TroveManager will be set via setTroveManager() after deployment
        liquidityCore = ILiquidityCore(_liquidityCore);
        sortedTroves = ISortedTroves(_sortedTroves);
        usdfToken = IUSDF(_usdfToken);
        priceOracle = IPriceOracle(_priceOracle);
    }

    // ============ External Functions ============

    /**
     * @notice Open a new trove (CDP)
     * @inheritdoc IBorrowerOperations
     * @dev V2: Calls TroveManager.updateTrove() instead of managing state locally
     */
    function openTrove(
        address asset,
        uint256 maxFeePercentage,
        uint256 collateralAmount,
        uint256 usdfAmount,
        address upperHint,
        address lowerHint
    ) external payable override nonReentrant whenNotPaused {
        // === Validation ===
        _requireValidAsset(asset);
        _requireNonZeroAmount(collateralAmount);
        _requireNonZeroAmount(usdfAmount);

        if (_isTroveActive[msg.sender][asset]) {
            revert TroveAlreadyExists(msg.sender, asset);
        }
        if (usdfAmount < MIN_NET_DEBT) {
            revert DebtBelowMinimum(usdfAmount, MIN_NET_DEBT);
        }

        // === Fee Calculation ===
        LocalVars memory vars;
        vars.price = _getAndCachePrice(asset);
        vars.borrowingFee = _calculateBorrowingFee(asset, usdfAmount);
        _requireValidMaxFeePercentage(maxFeePercentage, vars.borrowingFee, usdfAmount);

        // === Total Debt ===
        vars.totalDebt = usdfAmount + vars.borrowingFee + GAS_COMPENSATION;

        // === ICR Validation ===
        vars.icr = _calculateICR(collateralAmount, vars.totalDebt, vars.price);
        ICR_CACHE_SLOT.tstore(vars.icr);

        if (vars.icr < MCR) {
            revert InsufficientCollateralRatio(vars.icr, MCR);
        }

        // === Collateral Transfer ===
        IERC20(asset).safeTransferFrom(msg.sender, address(liquidityCore), collateralAmount);

        // === Update LiquidityCore ===
        liquidityCore.depositCollateral(asset, msg.sender, collateralAmount);
        liquidityCore.mintDebt(asset, msg.sender, vars.totalDebt);

        // === V2: Delegate to TroveManager (SINGLE SOURCE OF TRUTH) ===
        troveManager.updateTrove(msg.sender, asset, vars.totalDebt, collateralAmount, true);

        // === Local Tracking (for gas-efficient reads) ===
        _isTroveActive[msg.sender][asset] = true;
        _addAssetToUserList(msg.sender, asset);

        // === Insert into Sorted List ===
        vars.nominalICR = _calculateNominalICR(collateralAmount, vars.totalDebt);
        sortedTroves.insert(asset, msg.sender, vars.nominalICR, upperHint, lowerHint);

        // === Mint USDF ===
        usdfToken.mint(msg.sender, usdfAmount);

        if (vars.borrowingFee > 0) {
            usdfToken.mint(address(liquidityCore), vars.borrowingFee);
            emit BorrowingFeePaid(msg.sender, asset, vars.borrowingFee);
        }

        if (GAS_COMPENSATION > 0) {
            usdfToken.mint(address(liquidityCore), GAS_COMPENSATION);
        }

        emit TroveUpdated(msg.sender, asset, vars.totalDebt, collateralAmount, 0, 0);
    }

    // Helper struct to reduce stack variables
    struct LocalVars {
        uint256 price;
        uint256 borrowingFee;
        uint256 totalDebt;
        uint256 icr;
        uint256 nominalICR;
    }

    /**
     * @notice Close trove and repay all debt
     * @inheritdoc IBorrowerOperations
     * @dev V2: Calls TroveManager.closeTrove() to manage state
     */
    function closeTrove(address asset) external override nonReentrant whenNotPaused {
        _requireValidAsset(asset);

        // Check trove is active (local check for gas efficiency)
        if (!_isTroveActive[msg.sender][asset]) {
            revert TroveNotActive(msg.sender, asset);
        }

        // V2: Read from TroveManager (single source of truth)
        (uint256 debt, uint256 collateral) = troveManager.getTroveDebtAndColl(msg.sender, asset);

        // Burn USDF debt from user
        usdfToken.burnFrom(msg.sender, debt);

        // Update LiquidityCore
        liquidityCore.burnDebt(asset, msg.sender, debt);
        liquidityCore.withdrawCollateral(asset, msg.sender, collateral);

        // Return collateral to user
        liquidityCore.transferCollateral(asset, msg.sender, collateral);

        // V2: Delegate to TroveManager.closeTrove()
        // This will:
        // 1. Remove stake
        // 2. Update trove status to CLOSED
        // 3. Clear snapshots
        // 4. Remove from sortedTroves (FIX #2)
        // 5. Emit TroveUpdated event (FIX #3)
        troveManager.closeTrove(msg.sender, asset);

        // Update local tracking
        _isTroveActive[msg.sender][asset] = false;
        _removeAssetFromUserList(msg.sender, asset);

        emit TroveClosed(msg.sender, asset);
    }

    /**
     * @notice Adjust trove collateral and/or debt
     * @inheritdoc IBorrowerOperations
     * @dev V2: Calls TroveManager.updateTrove() for state changes
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
    ) external payable override nonReentrant whenNotPaused {
        _requireValidAsset(asset);

        if (!_isTroveActive[msg.sender][asset]) {
            revert TroveNotActive(msg.sender, asset);
        }

        // Use struct to avoid "stack too deep"
        AdjustVars memory vars;
        vars.asset = asset;

        // V2: Get current trove state from TroveManager
        (vars.currentDebt, vars.currentCollateral) = troveManager.getTroveDebtAndColl(msg.sender, asset);

        // Calculate new collateral
        vars.newCollateral = isCollateralIncrease
            ? vars.currentCollateral + collateralChange
            : vars.currentCollateral - collateralChange;

        // Calculate new debt
        vars.newDebt = isDebtIncrease
            ? vars.currentDebt + debtChange
            : vars.currentDebt - debtChange;

        // If increasing debt, apply borrowing fee
        if (isDebtIncrease && debtChange > 0) {
            vars.fee = _calculateBorrowingFee(vars.asset, debtChange);
            _requireValidMaxFeePercentage(maxFeePercentage, vars.fee, debtChange);
            vars.newDebt += vars.fee;
        }

        // Validate ICR
        vars.price = _getAndCachePrice(vars.asset);
        vars.newICR = _calculateICR(vars.newCollateral, vars.newDebt, vars.price);

        if (vars.newICR < MCR) {
            revert InsufficientCollateralRatio(vars.newICR, MCR);
        }

        // === Collateral changes ===
        if (collateralChange > 0) {
            if (isCollateralIncrease) {
                IERC20(vars.asset).safeTransferFrom(msg.sender, address(liquidityCore), collateralChange);
                liquidityCore.depositCollateral(vars.asset, msg.sender, collateralChange);
            } else {
                liquidityCore.withdrawCollateral(vars.asset, msg.sender, collateralChange);
                liquidityCore.transferCollateral(vars.asset, msg.sender, collateralChange);
            }
        }

        // === Debt changes ===
        if (debtChange > 0) {
            if (isDebtIncrease) {
                liquidityCore.mintDebt(vars.asset, msg.sender, debtChange + vars.fee);
                usdfToken.mint(msg.sender, debtChange);

                if (vars.fee > 0) {
                    usdfToken.mint(address(liquidityCore), vars.fee);
                    emit BorrowingFeePaid(msg.sender, vars.asset, vars.fee);
                }
            } else {
                usdfToken.burnFrom(msg.sender, debtChange);
                liquidityCore.burnDebt(vars.asset, msg.sender, debtChange);
            }
        }

        // V2: Update TroveManager (single source of truth)
        troveManager.updateTrove(msg.sender, vars.asset, vars.newDebt, vars.newCollateral, isDebtIncrease);

        // Reinsert in sorted list if needed
        if (collateralChange > 0 || debtChange > 0) {
            vars.newNominalICR = _calculateNominalICR(vars.newCollateral, vars.newDebt);
            sortedTroves.reInsert(vars.asset, msg.sender, vars.newNominalICR, upperHint, lowerHint);
        }

        emit TroveUpdated(msg.sender, vars.asset, vars.newDebt, vars.newCollateral, 0, 1);
    }

    // Struct for temporary variables to avoid stack-too-deep
    struct AdjustVars {
        uint256 currentDebt;
        uint256 currentCollateral;
        uint256 newCollateral;
        uint256 newDebt;
        uint256 fee;
        uint256 price;
        uint256 newICR;
        uint256 newNominalICR;
        address asset;
    }

    /**
     * @notice Claim surplus collateral after liquidation
     * @inheritdoc IBorrowerOperations
     */
    function claimCollateral(address asset) external override nonReentrant {
        _requireValidAsset(asset);

        uint256 surplus = liquidityCore.getPendingRewards(asset);

        if (surplus == 0) {
            revert InvalidAmount(0);
        }

        liquidityCore.claimRewards(asset, msg.sender, surplus);
        IERC20(asset).safeTransferFrom(address(liquidityCore), msg.sender, surplus);
    }

    // ============ View Functions ============
    // V2: Read from TroveManager (single source of truth)

    /**
     * @notice Get trove debt and collateral
     * @inheritdoc IBorrowerOperations
     * @dev V2: Reads from TroveManager instead of local storage
     */
    function getEntireDebtAndColl(
        address borrower,
        address asset
    ) external view override returns (uint256 debt, uint256 coll) {
        return troveManager.getTroveDebtAndColl(borrower, asset);
    }

    /**
     * @notice Calculate borrowing fee for amount
     * @inheritdoc IBorrowerOperations
     */
    function getBorrowingFee(
        address asset,
        uint256 usdfAmount
    ) external view override returns (uint256) {
        return _calculateBorrowingFee(asset, usdfAmount);
    }

    /**
     * @notice Get borrowing fee rate for asset
     * @inheritdoc IBorrowerOperations
     */
    function getBorrowingFeeRate(address asset) external view override returns (uint256) {
        uint256 rate = borrowingFeeRate[asset];
        return rate > 0 ? rate : BORROWING_FEE_FLOOR;
    }

    /**
     * @notice Check if trove is active
     * @inheritdoc IBorrowerOperations
     * @dev V2: Uses local mapping for gas-efficient reads
     */
    function isTroveActive(
        address borrower,
        address asset
    ) external view override returns (bool) {
        return _isTroveActive[borrower][asset];
    }

    /**
     * @notice Get all assets that a user has troves in
     * @param user The user address to query
     * @return assets Array of asset addresses the user has active troves in
     */
    function getUserTroveAssets(address user) external view returns (address[] memory) {
        return _userTroveAssets[user];
    }

    // ============ Internal Functions ============

    /**
     * @dev Get price from oracle with transient caching
     */
    function _getAndCachePrice(address asset) internal returns (uint256 price) {
        price = PRICE_CACHE_SLOT.tload();
        if (price > 0) {
            return price;
        }

        price = priceOracle.getPrice(asset);
        PRICE_CACHE_SLOT.tstore(price);
    }

    /**
     * @dev Calculate Individual Collateralization Ratio
     */
    function _calculateICR(
        uint256 collateral,
        uint256 debt,
        uint256 price
    ) internal pure returns (uint256) {
        if (debt == 0) return type(uint256).max;
        return GasOptimizedMath.mulDiv(collateral, price, debt);
    }

    /**
     * @dev Calculate Nominal ICR (without price, for sorting)
     */
    function _calculateNominalICR(
        uint256 collateral,
        uint256 debt
    ) internal pure returns (uint256) {
        if (debt == 0) return type(uint256).max;
        return (collateral * NICR_PRECISION) / debt;
    }

    /**
     * @dev Calculate borrowing fee
     */
    function _calculateBorrowingFee(
        address asset,
        uint256 usdfAmount
    ) internal view returns (uint256 fee) {
        uint256 rate = borrowingFeeRate[asset];
        if (rate == 0) rate = BORROWING_FEE_FLOOR;
        return GasOptimizedMath.mulDiv(usdfAmount, rate, DECIMAL_PRECISION);
    }

    /**
     * @dev Validate asset address
     */
    function _requireValidAsset(address asset) internal pure {
        if (asset == address(0)) {
            revert InvalidAsset(asset);
        }
    }

    /**
     * @dev Validate amount is non-zero
     */
    function _requireNonZeroAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
    }

    /**
     * @dev Validate max fee percentage
     */
    function _requireValidMaxFeePercentage(
        uint256 maxFeePercentage,
        uint256 actualFee,
        uint256 amount
    ) internal pure {
        if (maxFeePercentage < BORROWING_FEE_FLOOR || maxFeePercentage > MAX_BORROWING_FEE) {
            revert InvalidMaxFeePercentage(maxFeePercentage);
        }

        uint256 feePercentage = GasOptimizedMath.mulDiv(actualFee, DECIMAL_PRECISION, amount);
        if (feePercentage > maxFeePercentage) {
            revert FeeExceedsMaximum(actualFee, maxFeePercentage);
        }
    }

    /**
     * @dev Add asset to user's trove list
     */
    function _addAssetToUserList(address user, address asset) internal {
        if (_userAssetIndex[user][asset] == 0) {
            _userTroveAssets[user].push(asset);
            _userAssetIndex[user][asset] = _userTroveAssets[user].length;
        }
    }

    /**
     * @dev Remove asset from user's trove list using swap-and-pop
     */
    function _removeAssetFromUserList(address user, address asset) internal {
        uint256 index = _userAssetIndex[user][asset];
        if (index == 0) return;

        uint256 arrayIndex = index - 1;
        uint256 lastIndex = _userTroveAssets[user].length - 1;

        if (arrayIndex != lastIndex) {
            address lastAsset = _userTroveAssets[user][lastIndex];
            _userTroveAssets[user][arrayIndex] = lastAsset;
            _userAssetIndex[user][lastAsset] = index;
        }

        _userTroveAssets[user].pop();
        delete _userAssetIndex[user][asset];
    }

    // ============ Admin Functions ============

    /**
     * @notice Set TroveManager address (one-time, for circular dependency resolution)
     * @param _troveManager TroveManager contract address
     * @dev V2: Allows setting TroveManager after deployment to resolve circular dependency
     */
    function setTroveManager(address _troveManager) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        require(_troveManager != address(0), "BO: Invalid TroveManager");
        require(address(troveManager) == address(0), "BO: TroveManager already set");
        troveManager = ITroveManager(_troveManager);
    }

    /**
     * @notice Set borrowing fee rate for asset
     * @param asset Collateral asset
     * @param rate Fee rate in 1e18 precision (e.g., 5e15 = 0.5%)
     */
    function setBorrowingFeeRate(
        address asset,
        uint256 rate
    ) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        require(rate >= BORROWING_FEE_FLOOR && rate <= MAX_BORROWING_FEE, "BO: Invalid rate");
        borrowingFeeRate[asset] = rate;
    }
}

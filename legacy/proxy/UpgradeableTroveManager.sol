// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/IStabilityPool.sol";
import "../tokens/USDF.sol";
import "../core/PriceOracle.sol";
import "../core/SortedTroves.sol";
import "../libraries/OptimizedDataStructures.sol";

/**
 * @title UpgradeableTroveManager
 * @dev Upgradeable version of TroveManager using proxy pattern to solve circular dependencies
 */
contract UpgradeableTroveManager is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ITroveManager 
{
    using OptimizedDataStructures for OptimizedDataStructures.CircularBuffer;
    using OptimizedDataStructures for OptimizedDataStructures.PackedTrove;
    
    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MIN_COLLATERAL_RATIO = 1.35e18; // 135%
    uint256 public constant LIQUIDATION_THRESHOLD = 1.1e18; // 110%
    uint256 public constant CCR = 1.5e18; // Critical collateralization ratio
    uint256 public constant MCR = 1.1e18; // Minimum collateralization ratio
    uint256 public constant LIQUIDATION_RESERVE = 200e18; // 200 USDF
    uint256 public constant MAX_BORROWING_FEE = 0.05e18; // 5%
    uint256 public constant BORROWING_FEE_FLOOR = 0.005e18; // 0.5%
    
    
    // Security limitsss
    uint256 public constant MAX_TROVES_PER_USER = 10;
    uint256 public constant MAX_LIQUIDATION_AMOUNT = 1000000e18; // 1M USDF
    uint256 public constant MIN_LIQUIDATION_AMOUNT = 100e18; // 100 USDF
    
    // Access control roles
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant BORROWER_ROLE = keccak256("BORROWER_ROLE");
    
    // State variables (non-immutable for upgradeability)
    USDF public usdfToken;
    IStabilityPool public stabilityPool;
    PriceOracle public priceOracle;
    SortedTroves public sortedTroves;
    address public borrowerOperations;
    address public activePool;
    address public defaultPool;
    address public collSurplusPool;
    address public gasPool;
    
    // Trove storage
    mapping(address => mapping(address => OptimizedDataStructures.PackedTrove)) public packedTroves;
    mapping(address => uint256) public userTroveCount;
    mapping(address => uint256) public totalStakes;
    mapping(address => uint256) public totalCollateral;
    mapping(address => uint256) public totalDebt;
    
    // Liquidation rewards
    mapping(address => uint256) public L_Collateral;
    mapping(address => uint256) public L_Debt;
    
    // Snapshots for reward calculations
    mapping(address => mapping(address => uint256)) public L_CollateralSnapshots;
    mapping(address => mapping(address => uint256)) public L_DebtSnapshots;
    mapping(address => mapping(address => uint256)) public troveStakes;
    
    // Events
    event TroveUpdatedSecure(
        address indexed borrower,
        address indexed asset,
        uint256 debt,
        uint256 coll,
        uint256 stake,
        TroveManagerOperation operation,
        uint256 gasUsed,
        uint256 blockNumber
    );
    
    event SecurityCheck(
        address indexed caller,
        string checkType,
        bool passed,
        string details
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initialize the contract
     * @param _accessControl Address of the access control contract
     * @param _usdfToken Address of the USDF token
     * @param _priceOracle Address of the price oracle
     * @param _sortedTroves Address of the sorted troves contract
     */
    function initialize(
        address _accessControl,
        address _usdfToken,
        address _priceOracle,
        address _sortedTroves
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        
        require(_accessControl != address(0), "Invalid access control address");
        require(_usdfToken != address(0), "Invalid USDF token address");
        require(_priceOracle != address(0), "Invalid price oracle address");
        require(_sortedTroves != address(0), "Invalid sorted troves address");
        
        usdfToken = USDF(_usdfToken);
        priceOracle = PriceOracle(_priceOracle);
        sortedTroves = SortedTroves(_sortedTroves);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @dev Set the remaining contract addresses after all contracts are deployed
     * This solves the circular dependency issue
     */
    function setContractAddresses(
        address _stabilityPool,
        address _borrowerOperations,
        address _activePool,
        address _defaultPool,
        address _collSurplusPool,
        address _gasPool
    ) external onlyRole(ADMIN_ROLE) {
        require(_stabilityPool != address(0), "Invalid stability pool address");
        require(_borrowerOperations != address(0), "Invalid borrower operations address");
        require(_activePool != address(0), "Invalid active pool address");
        require(_defaultPool != address(0), "Invalid default pool address");
        require(_collSurplusPool != address(0), "Invalid coll surplus pool address");
        require(_gasPool != address(0), "Invalid gas pool address");
        
        stabilityPool = IStabilityPool(_stabilityPool);
        borrowerOperations = _borrowerOperations;
        activePool = _activePool;
        defaultPool = _defaultPool;
        collSurplusPool = _collSurplusPool;
        gasPool = _gasPool;
    }
    
    /**
     * @dev Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
    
    /**
     * @dev Update a trove's debt and collateral
     */
    function updateTrove(
        address borrower,
        address asset,
        uint256 collChange,
        bool isCollIncrease,
        uint256 debtChange,
        bool isDebtIncrease
    ) external override whenNotPaused nonReentrant returns (uint256, uint256) {
        require(msg.sender == borrowerOperations, "Only BorrowerOperations can call this");
        require(borrower != address(0), "Invalid borrower address");
        require(asset != address(0), "Invalid asset address");
        require(userTroveCount[borrower] < MAX_TROVES_PER_USER, "Too many troves");
        
        uint256 gasStart = gasleft();
        
        // Get current trove data
        (uint256 currentDebt, uint256 currentColl, uint256 pendingCollReward, uint256 pendingDebtReward) = 
            _getTroveData(borrower, asset);
        
        // Apply pending rewards
        currentColl = _safeAdd(currentColl, pendingCollReward);
        currentDebt = _safeAdd(currentDebt, pendingDebtReward);
        
        // Calculate new values
        uint256 newColl = isCollIncrease ? 
            _safeAdd(currentColl, collChange) : 
            _safeSub(currentColl, collChange);
        uint256 newDebt = isDebtIncrease ? 
            _safeAdd(currentDebt, debtChange) : 
            _safeSub(currentDebt, debtChange);
        
        // Validate new collateral ratio
        uint256 price = priceOracle.getPrice(asset);
        uint256 newICR = _calculateICR(newColl, newDebt, price);
        require(newICR >= MCR, "Insufficient collateral ratio");
        
        // Update trove
        _updateTroveData(borrower, asset, newDebt, newColl);
        
        // Update global totals
        _updateGlobalTotals(asset, currentDebt, newDebt, currentColl, newColl);
        
        uint256 gasUsed = gasStart - gasleft();
        emit TroveUpdatedSecure(
            borrower, 
            asset, 
            newDebt, 
            newColl, 
            troveStakes[borrower][asset],
            TroveManagerOperation.updateTrove,
            gasUsed,
            block.number
        );
        
        return (newDebt, newColl);
    }
    
    /**
     * @dev Liquidate a trove
     */
    function liquidate(address borrower, address asset) 
        external 
        
        whenNotPaused 
        nonReentrant 
        onlyRole(LIQUIDATOR_ROLE) 
       
    {
        require(borrower != address(0), "Invalid borrower address");
        require(asset != address(0), "Invalid asset address");
        
        // Get trove data
        (uint256 debt, uint256 coll,,) = _getTroveData(borrower, asset);
        require(debt > 0, "Trove does not exist");
        
        // Check if trove is liquidatable
        uint256 price = priceOracle.getPrice(asset);
        uint256 icr = _calculateICR(coll, debt, price);
        require(icr < MCR, "Trove not liquidatable");
        
        // Validate liquidation amount
        require(debt >= MIN_LIQUIDATION_AMOUNT, "Debt too small to liquidate");
        require(debt <= MAX_LIQUIDATION_AMOUNT, "Debt too large for single liquidation");
        
        // Execute liquidation
        _executeLiquidation(borrower, asset, debt, coll, price);
        
        
    }
    
    // Internal functions
    function _getTroveData(address borrower, address asset) 
        internal 
        view 
        returns (uint256 debt, uint256 coll, uint256 pendingCollReward, uint256 pendingDebtReward) 
    {
        OptimizedDataStructures.PackedTrove memory packed = packedTroves[borrower][asset];
        (debt, coll,,) = packed.unpackTrove();
        (pendingCollReward, pendingDebtReward) = _getPendingRewards(borrower, asset);
    }
    
    function _getPendingRewards(address borrower, address asset) 
        internal 
        view 
        returns (uint256 pendingCollReward, uint256 pendingDebtReward) 
    {
        uint256 stake = troveStakes[borrower][asset];
        if (stake == 0) return (0, 0);
        
        uint256 collSnapshot = L_CollateralSnapshots[borrower][asset];
        uint256 debtSnapshot = L_DebtSnapshots[borrower][asset];
        
        pendingCollReward = _safeMul(stake, L_Collateral[asset] - collSnapshot) / DECIMAL_PRECISION;
        pendingDebtReward = _safeMul(stake, L_Debt[asset] - debtSnapshot) / DECIMAL_PRECISION;
    }
    
    function _calculateICR(uint256 coll, uint256 debt, uint256 price) 
        internal 
        pure 
        returns (uint256) 
    {
        if (debt == 0) return type(uint256).max;
        return _safeMul(coll, price) / debt;
    }
    
    function _updateTroveData(address borrower, address asset, uint256 debt, uint256 coll) internal {
        packedTroves[borrower][asset] = OptimizedDataStructures.packTrove(
            debt, coll, block.timestamp, 1 // status: active
        );
    }
    
    function _updateGlobalTotals(
        address asset, 
        uint256 oldDebt, 
        uint256 newDebt, 
        uint256 oldColl, 
        uint256 newColl
    ) internal {
        if (newDebt >= oldDebt) {
            totalDebt[asset] = _safeAdd(totalDebt[asset], newDebt - oldDebt);
        } else {
            totalDebt[asset] = _safeSub(totalDebt[asset], oldDebt - newDebt);
        }
        
        if (newColl >= oldColl) {
            totalCollateral[asset] = _safeAdd(totalCollateral[asset], newColl - oldColl);
        } else {
            totalCollateral[asset] = _safeSub(totalCollateral[asset], oldColl - newColl);
        }
    }
    
    function _executeLiquidation(
        address borrower,
        address asset,
        uint256 debt,
        uint256 coll,
        uint256 price
    ) internal {
        // Apply pending rewards first
        (uint256 pendingCollReward, uint256 pendingDebtReward) = _getPendingRewards(borrower, asset);
        uint256 totalTroveDebt = _safeAdd(debt, pendingDebtReward);
        uint256 totalColl = _safeAdd(coll, pendingCollReward);
        
        // Close the trove
        packedTroves[borrower][asset] = OptimizedDataStructures.packTrove(
            0, 0, block.timestamp, 3 // closedByLiquidation
        );
        
        // Remove from sorted troves
        sortedTroves.remove(asset, borrower);
        userTroveCount[borrower]--;
        
        // Update global totals
        totalDebt[asset] = _safeSub(totalDebt[asset], totalTroveDebt);
        totalCollateral[asset] = _safeSub(totalCollateral[asset], totalColl);
        
        // Update total stakes
        uint256 stake = troveStakes[borrower][asset];
        totalStakes[asset] = _safeSub(totalStakes[asset], stake);
        troveStakes[borrower][asset] = 0;
        
        emit TroveLiquidated(
            borrower, 
            asset, 
            totalTroveDebt, 
            totalColl, 
            TroveManagerOperation.liquidateInNormalMode
        );
    }
    
    // Safe math functions
    function _safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "Addition overflow");
        return c;
    }
    
    function _safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "Subtraction underflow");
        return a - b;
    }
    
    function _safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "Multiplication overflow");
        return c;
    }
    
    // Missing interface methods implementation
    
    /**
     * @dev Get current ICR for a trove
     */
    function getCurrentICR(address borrower, address asset) external view override returns (uint256) {
        (uint256 debt, uint256 coll,,) = _getTroveData(borrower, asset);
        if (debt == 0) return type(uint256).max;
        
        uint256 price = priceOracle.getPrice(asset);
        return _calculateICR(coll, debt, price);
    }
    
    /**
     * @dev Get trove debt and collateral
     */
    function getTroveDebtAndColl(address borrower, address asset) 
        external 
        view 
        override 
        returns (uint256 debt, uint256 coll) 
    {
        (debt, coll,,) = _getTroveData(borrower, asset);
    }
    
    /**
     * @dev Get trove status
     */
    function getTroveStatus(address borrower, address asset) external view override returns (uint256) {
        OptimizedDataStructures.PackedTrove memory packed = packedTroves[borrower][asset];
        (,,, uint256 status) = packed.unpackTrove();
        return status;
    }
    
    /**
     * @dev Liquidate multiple troves
     */
    function liquidateTroves(address asset, uint256 n) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        onlyRole(LIQUIDATOR_ROLE) 
    {
        require(n > 0, "Must liquidate at least 1 trove");
        require(n <= 50, "Too many troves to liquidate at once");
        
        uint256 liquidatedCount = 0;
        
        // Get sorted list of troves from lowest to highest ICR
        address currentTrove = sortedTroves.getFirst(asset);
        uint256 price = priceOracle.getPrice(asset);
        
        for (uint256 i = 0; i < n && currentTrove != address(0); i++) {
            address nextTrove = sortedTroves.getNext(asset, currentTrove);
            
            // Check if trove is undercollateralized
            (uint256 debt, uint256 coll,,) = _getTroveData(currentTrove, asset);
            if (debt > 0) {
                uint256 ICR = _calculateICR(coll, debt, price);
                
                if (ICR < MCR) {
                    _executeLiquidation(currentTrove, asset, debt, coll, price);
                    liquidatedCount++;
                } else {
                    // Troves are sorted by ICR, so if current trove is sufficiently collateralized,
                    // all remaining troves will be too
                    break;
                }
            }
            
            currentTrove = nextTrove;
        }
        
        require(liquidatedCount > 0, "No troves were liquidated");
    }
    
    /**
     * @dev Redeem collateral
     */
    function redeemCollateral(
        address asset,
        uint256 usdfAmount,
        address firstRedemptionHint,
        address upperPartialRedemptionHint,
        address lowerPartialRedemptionHint,
        uint256 partialRedemptionHintNICR,
        uint256 maxIterations,
        uint256 maxFeePercentage
    ) external override whenNotPaused nonReentrant {
        require(usdfAmount > 0, "USDF amount must be positive");
        require(maxIterations > 0 && maxIterations <= 50, "Invalid max iterations");
        require(maxFeePercentage <= MAX_BORROWING_FEE, "Max fee percentage too high");
        require(usdfToken.balanceOf(msg.sender) >= usdfAmount, "Insufficient USDF balance");
        
        uint256 price = priceOracle.getPrice(asset);
        uint256 remainingUSDF = usdfAmount;
        uint256 totalCollateralRedeemed = 0;
        uint256 iterations = 0;
        
        // Start from the trove with the lowest ICR (first in sorted list)
        address currentTrove = firstRedemptionHint != address(0) ? 
            firstRedemptionHint : sortedTroves.getLast(asset); // Start from highest ICR for redemption
            
        while (remainingUSDF > 0 && currentTrove != address(0) && iterations < maxIterations) {
            (uint256 debt, uint256 coll,,) = _getTroveData(currentTrove, asset);
            
            if (debt > 0) {
                uint256 ICR = _calculateICR(coll, debt, price);
                require(ICR >= MCR, "Cannot redeem from undercollateralized trove");
                
                uint256 maxRedeemableDebt = debt > LIQUIDATION_RESERVE ? 
                    debt - LIQUIDATION_RESERVE : 0;
                    
                if (maxRedeemableDebt > 0) {
                    uint256 debtToRedeem = remainingUSDF > maxRedeemableDebt ? 
                        maxRedeemableDebt : remainingUSDF;
                    
                    // Calculate collateral to redeem
                    uint256 collToRedeem = (debtToRedeem * DECIMAL_PRECISION) / price;
                    
                    if (collToRedeem <= coll) {
                        // Update trove
                        uint256 newDebt = debt - debtToRedeem;
                        uint256 newColl = coll - collToRedeem;
                        
                        // Update trove storage
                        _updateTroveData(currentTrove, asset, newDebt, newColl);
                        
                        // Update global totals
                        totalDebt[asset] = _safeSub(totalDebt[asset], debtToRedeem);
                        totalCollateral[asset] = _safeSub(totalCollateral[asset], collToRedeem);
                        
                        // Update sorted troves if trove still has debt
                        if (newDebt > 0) {
                            uint256 newICR = _calculateICR(newColl, newDebt, price);
                            sortedTroves.reInsert(asset, currentTrove, newICR, upperPartialRedemptionHint, lowerPartialRedemptionHint);
                        } else {
                            sortedTroves.remove(asset, currentTrove);
                            userTroveCount[currentTrove]--;
                        }
                        
                        remainingUSDF = _safeSub(remainingUSDF, debtToRedeem);
                        totalCollateralRedeemed = _safeAdd(totalCollateralRedeemed, collToRedeem);
                        
                        emit TroveUpdated(
                            currentTrove,
                            asset,
                            newDebt,
                            newColl,
                            0, // stake
                            TroveManagerOperation.redeemCollateral
                        );
                    }
                }
            }
            
            currentTrove = sortedTroves.getPrev(asset, currentTrove);
            iterations++;
        }
        
        require(remainingUSDF < usdfAmount, "No redemption occurred");
        
        uint256 actualUSDFRedeemed = usdfAmount - remainingUSDF;
        
        // Calculate and charge redemption fee
        uint256 redemptionFee = (actualUSDFRedeemed * BORROWING_FEE_FLOOR) / DECIMAL_PRECISION;
        uint256 collateralAfterFee = totalCollateralRedeemed > redemptionFee ? 
            totalCollateralRedeemed - redemptionFee : 0;
            
        require(redemptionFee <= (totalCollateralRedeemed * maxFeePercentage) / DECIMAL_PRECISION, "Fee exceeds maximum");
        
        // Burn USDF from redeemer
        usdfToken.burnFrom(msg.sender, actualUSDFRedeemed);
        
        emit Redemption(msg.sender, actualUSDFRedeemed, collateralAfterFee, redemptionFee);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/IStabilityPool.sol";
import "../tokens/USDF.sol";
import "../core/PriceOracle.sol";
import "../core/SortedTroves.sol";

/**
 * @title UpgradeableBorrowerOperations
 * @dev Upgradeable version of BorrowerOperations using proxy pattern
 */
contract UpgradeableBorrowerOperations is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IBorrowerOperations 
{
    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MIN_DEBT = 2000e18; // 2000 USDF minimum debt
    uint256 public constant BORROWING_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%
    uint256 public constant MAX_BORROWING_FEE = DECIMAL_PRECISION / 100 * 5; // 5%
    uint256 public constant CCR = 150 * DECIMAL_PRECISION / 100; // 150%
    uint256 public constant MCR = 110 * DECIMAL_PRECISION / 100; // 110%
    
    // Security limits
    uint256 public constant MAX_SINGLE_OPERATION = 10000000e18; // 10M USDF
    uint256 public constant MIN_COLLATERAL_CHANGE = 1e15; // 0.001 ETH minimum
    
    // Access control roles
    bytes32 public constant BORROWER_ROLE = keccak256("BORROWER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // Contract references
    ITroveManager public troveManager;
    IStabilityPool public stabilityPool;
    USDF public usdfToken;
    PriceOracle public priceOracle;
    SortedTroves public sortedTroves;
    address public activePool;
    address public defaultPool;
    address public collSurplusPool;
    address public gasPool;
    
    // State variables
    mapping(address => uint256) public borrowingFees;
    uint256 public baseRate;
    uint256 public lastFeeOperationTime;
    
    // Events
    event TroveCreated(address indexed borrower, address indexed asset, uint256 debt, uint256 coll, uint256 stake);
    event TroveUpdated(address indexed borrower, address indexed asset, uint256 debt, uint256 coll, uint256 stake, BorrowerOperation operation);
    event BorrowingFeePaid(address indexed borrower, address indexed asset, uint256 fee);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initialize the contract
     */
    function initialize(
        address _accessControl,
        address _usdfToken,
        address _priceOracle,
        address _sortedTroves
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
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
        _grantRole(BORROWER_ROLE, msg.sender);
    }
    
    /**
     * @dev Set the remaining contract addresses after all contracts are deployed
     */
    function setContractAddresses(
        address _troveManager,
        address _stabilityPool,
        address _activePool,
        address _defaultPool,
        address _collSurplusPool,
        address _gasPool
    ) external onlyRole(ADMIN_ROLE) {
        require(_troveManager != address(0), "Invalid trove manager address");
        require(_stabilityPool != address(0), "Invalid stability pool address");
        require(_activePool != address(0), "Invalid active pool address");
        require(_defaultPool != address(0), "Invalid default pool address");
        require(_collSurplusPool != address(0), "Invalid coll surplus pool address");
        require(_gasPool != address(0), "Invalid gas pool address");
        
        troveManager = ITroveManager(_troveManager);
        stabilityPool = IStabilityPool(_stabilityPool);
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
     * @dev Open a new trove
     */
    function openTrove(
        address asset,
        uint256 maxFeePercentage,
        uint256 collAmount,
        uint256 debtAmount,
        address upperHint,
        address lowerHint
    ) external payable override nonReentrant {
        require(asset != address(0), "Invalid asset");
        require(collAmount >= MIN_COLLATERAL_CHANGE, "Insufficient collateral");
        require(debtAmount >= MIN_DEBT, "Debt below minimum");
        require(debtAmount <= MAX_SINGLE_OPERATION, "Debt exceeds maximum");
        require(maxFeePercentage <= MAX_BORROWING_FEE, "Max fee too high");
        
        // Get current price
        uint256 price = priceOracle.getPrice(asset);
        require(price > 0, "Invalid price");
        
        // Calculate ICR and validate
        uint256 icr = _calculateICR(collAmount, debtAmount, price);
        require(icr >= MCR, "ICR below minimum");
        
        // Calculate and check borrowing fee
        uint256 borrowingFee = _calculateBorrowingFee(debtAmount);
        require(borrowingFee <= (debtAmount * maxFeePercentage) / DECIMAL_PRECISION, "Fee exceeds maximum");
        
        uint256 totalDebt = debtAmount + borrowingFee;
        
        // Handle collateral deposit
        if (asset == address(0)) { // ETH
            require(msg.value == collAmount, "Incorrect ETH amount");
            _sendETH(activePool, collAmount);
        } else {
            IERC20(asset).transferFrom(msg.sender, activePool, collAmount);
        }
        
        // Update trove in TroveManager
        troveManager.updateTrove(msg.sender, asset, collAmount, true, totalDebt, true);
        
        // Insert trove into sorted list
        sortedTroves.insert(asset, msg.sender, icr, upperHint, lowerHint);
        
        // Mint USDF to borrower
        usdfToken.mint(msg.sender, debtAmount);
        
        // Pay borrowing fee if any
        if (borrowingFee > 0) {
            usdfToken.mint(address(this), borrowingFee);
            _payFee(asset, borrowingFee);
            emit BorrowingFeePaid(msg.sender, asset, borrowingFee);
        }
        
        emit TroveCreated(msg.sender, asset, totalDebt, collAmount, 0);
    }
    
    /**
     * @dev Close a trove
     */
    function closeTrove(address asset) external override nonReentrant {
        require(asset != address(0), "Invalid asset");
        
        // Get trove data from TroveManager
        (uint256 debt, uint256 coll) = troveManager.getTroveDebtAndColl(msg.sender, asset);
        
        require(debt > 0, "Trove does not exist");
        
        uint256 totalDebt = debt;
        uint256 totalColl = coll;
        
        // Burn USDF from borrower
        usdfToken.burnFrom(msg.sender, totalDebt);
        
        // Update trove to zero values
        troveManager.updateTrove(msg.sender, asset, totalColl, false, totalDebt, false);
        
        // Remove from sorted troves
        sortedTroves.remove(asset, msg.sender);
        
        // Return collateral to borrower
        if (asset == address(0)) { // ETH
            _sendETH(msg.sender, totalColl);
        } else {
            IERC20(asset).transfer(msg.sender, totalColl);
        }
        
        emit TroveUpdated(msg.sender, asset, 0, 0, 0, BorrowerOperation.closeTrove);
    }
    
    /**
     * @dev Adjust a trove by changing collateral and/or debt (internal)
     */
    function _adjustTrove(
        address asset,
        uint256 maxFeePercentage,
        uint256 collChange,
        bool isCollIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        address upperHint,
        address lowerHint
    ) internal {
        require(asset != address(0), "Invalid asset");
        require(collChange > 0 || debtChange > 0, "No changes specified");
        
        // Get current trove data
        (uint256 currentDebt, uint256 currentColl) = troveManager.getTroveDebtAndColl(msg.sender, asset);
        require(currentDebt > 0, "Trove does not exist");
        
        // Calculate new values
        uint256 newColl = isCollIncrease ? 
            currentColl + collChange : 
            _safeSub(currentColl, collChange, "Insufficient collateral");
        
        uint256 newDebt = currentDebt;
        uint256 borrowingFee = 0;
        
        if (debtChange > 0) {
            if (isDebtIncrease) {
                borrowingFee = _calculateBorrowingFee(debtChange);
                require(borrowingFee <= (debtChange * maxFeePercentage) / DECIMAL_PRECISION, "Fee exceeds maximum");
                newDebt = currentDebt + debtChange + borrowingFee;
                
                // Mint USDF to borrower
                usdfToken.mint(msg.sender, debtChange);
                
                // Handle borrowing fee
                if (borrowingFee > 0) {
                    usdfToken.mint(address(this), borrowingFee);
                    _payFee(asset, borrowingFee);
                    emit BorrowingFeePaid(msg.sender, asset, borrowingFee);
                }
            } else {
                newDebt = _safeSub(currentDebt, debtChange, "Debt change too large");
                // Burn USDF from borrower
                usdfToken.burnFrom(msg.sender, debtChange);
            }
            
            require(newDebt >= MIN_DEBT, "New debt below minimum");
            require(newDebt <= MAX_SINGLE_OPERATION, "New debt exceeds maximum");
        }
        
        // Validate new ICR
        uint256 price = priceOracle.getPrice(asset);
        uint256 newICR = _calculateICR(newColl, newDebt, price);
        require(newICR >= MCR, "New ICR below minimum");
        
        // Handle collateral changes
        if (collChange > 0) {
            if (isCollIncrease) {
                if (asset == address(0)) { // ETH
                    require(msg.value == collChange, "Incorrect ETH amount");
                    _sendETH(activePool, collChange);
                } else {
                    IERC20(asset).transferFrom(msg.sender, activePool, collChange);
                }
            } else {
                // Return collateral to borrower
                if (asset == address(0)) { // ETH
                    _sendETH(msg.sender, collChange);
                } else {
                    IERC20(asset).transfer(msg.sender, collChange);
                }
            }
        }
        
        // Update trove
        troveManager.updateTrove(
            msg.sender, 
            asset, 
            collChange, 
            isCollIncrease, 
            debtChange + borrowingFee, 
            isDebtIncrease
        );
        
        // Update position in sorted troves if ICR changed
        sortedTroves.reInsert(asset, msg.sender, newICR, upperHint, lowerHint);
        
        emit TroveUpdated(msg.sender, asset, newDebt, newColl, 0, BorrowerOperation.adjustTrove);
    }
    
    // Internal functions
    function _calculateICR(uint256 coll, uint256 debt, uint256 price) 
        internal 
        pure 
        returns (uint256) 
    {
        if (debt == 0) return type(uint256).max;
        return (coll * price) / debt;
    }
    
    function _calculateBorrowingFee(uint256 debtAmount) internal view returns (uint256) {
        uint256 decayedBaseRate = _calcDecayedBaseRate();
        uint256 feeRate = _max(BORROWING_FEE_FLOOR, decayedBaseRate);
        return (debtAmount * feeRate) / DECIMAL_PRECISION;
    }
    
    function _calcDecayedBaseRate() internal view returns (uint256) {
        uint256 minutesPassed = (block.timestamp - lastFeeOperationTime) / 60;
        uint256 decayFactor = _decPow(minutesPassed);
        return (baseRate * decayFactor) / DECIMAL_PRECISION;
    }
    
    function _decPow(uint256 minute) internal pure returns (uint256) {
        // Simplified decay function - in production use more sophisticated calculation
        if (minute >= 525600) return 0; // 1 year
        return DECIMAL_PRECISION - (minute * DECIMAL_PRECISION) / 525600;
    }
    
    function _payFee(address asset, uint256 fee) internal {
        // In a real implementation, this would distribute fees appropriately
        // For now, just transfer to the contract
    }
    
    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }
    
    function _safeSub(uint256 a, uint256 b, string memory errorMessage) 
        internal 
        pure 
        returns (uint256) 
    {
        require(b <= a, errorMessage);
        return a - b;
    }
    
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
    
    // Missing interface methods implementation
    
    /**
     * @dev Add collateral to existing trove
     */
    function addColl(
        address asset, 
        uint256 collAmount, 
        address upperHint, 
        address lowerHint
    ) external payable override nonReentrant {
        _adjustTrove(asset, 0, collAmount, true, 0, false, upperHint, lowerHint);
    }
    
    /**
     * @dev Withdraw collateral from existing trove
     */
    function withdrawColl(
        address asset, 
        uint256 collAmount, 
        address upperHint, 
        address lowerHint
    ) external override nonReentrant {
        _adjustTrove(asset, 0, collAmount, false, 0, false, upperHint, lowerHint);
    }
    
    /**
     * @dev Withdraw USDF from existing trove
     */
    function withdrawUSDF(
        address asset, 
        uint256 maxFeePercentage, 
        uint256 usdfAmount, 
        address upperHint, 
        address lowerHint
    ) external override nonReentrant {
        _adjustTrove(asset, maxFeePercentage, 0, false, usdfAmount, true, upperHint, lowerHint);
    }
    
    /**
     * @dev Repay USDF to existing trove
     */
    function repayUSDF(
        address asset, 
        uint256 usdfAmount, 
        address upperHint, 
        address lowerHint
    ) external override nonReentrant {
        _adjustTrove(asset, 0, 0, false, usdfAmount, false, upperHint, lowerHint);
    }
    
    /**
     * @dev Get composite debt including gas compensation
     */
    function getCompositeDebt(
        address asset, 
        uint256 debt
    ) external pure override returns (uint256) {
        return debt + 200e18; // Gas compensation
    }
    
    /**
     * @dev Get current borrowing fee
     */
    function getBorrowingFee(
        address asset, 
        uint256 usdfDebt
    ) external view override returns (uint256) {
        return _calculateBorrowingFee(usdfDebt);
    }
    
    /**
     * @dev Get borrowing fee with decay applied
     */
    function getBorrowingFeeWithDecay(
        address asset, 
        uint256 usdfDebt
    ) external view override returns (uint256) {
        return _calculateBorrowingFee(usdfDebt);
    }
    
    /**
     * @dev Override adjustTrove with correct signature
     */
    function adjustTrove(
        address asset,
        uint256 maxFeePercentage,
        uint256 collWithdrawal,
        uint256 usdfChange,
        bool isDebtIncrease,
        address upperHint,
        address lowerHint
    ) external payable override nonReentrant {
        // Determine if it's a collateral increase (msg.value > 0) or decrease (collWithdrawal > 0)
        uint256 collChange = msg.value > 0 ? msg.value : collWithdrawal;
        bool isCollIncrease = msg.value > 0;
        
        _adjustTrove(
            asset,
            maxFeePercentage,
            collChange,
            isCollIncrease,
            usdfChange,
            isDebtIncrease,
            upperHint,
            lowerHint
        );
    }
}
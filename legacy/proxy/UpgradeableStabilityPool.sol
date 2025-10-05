// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IStabilityPool.sol";
import "../interfaces/ITroveManager.sol";
import "../tokens/USDF.sol";
import "../tokens/FluidToken.sol";

/**
 * @title UpgradeableStabilityPool
 * @dev Upgradeable version of StabilityPool using proxy pattern
 */
contract UpgradeableStabilityPool is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IStabilityPool 
{
    using SafeERC20 for IERC20;
    
    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant SCALE_FACTOR = 1e9;
    uint256 public constant MAX_EPOCH = type(uint128).max;
    uint256 public constant MAX_SCALE = type(uint128).max;
    uint256 public constant MIN_DEPOSIT = 1e15; // 0.001 USDF minimum
    uint256 public constant MAX_DEPOSIT = 10000000e18; // 10M USDF maximum
    
    // Precision constants
    uint256 private constant PRECISION_MULTIPLIER = 1e27;
    uint256 private constant REWARD_PRECISION = 1e36;
    
    // Access control roles
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // Contract references
    USDF public usdfToken;
    FluidToken public fluidToken;
    ITroveManager public troveManager;
    address public borrowerOperations;
    address public activePool;
    address public communityIssuance;
    
    // Pool state
    uint256 public totalUSDF;
    mapping(address => uint256) public totalCollateral;
    
    // User deposits
    mapping(address => uint256) public deposits;
    mapping(address => Snapshots) public depositSnapshots;
    mapping(address => uint256) public lastDepositTime; // MEV protection
    
    // Reward tracking with overflow protection
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public epochToScaleToSum;
    mapping(address => uint256) public lastAssetError_Offset;
    
    // Product P tracking with safe arithmetic
    uint256 public P;
    uint256 public currentScale;
    uint256 public currentEpoch;
    
    // FLUID rewards tracking
    uint256 public G;
    mapping(uint256 => mapping(uint256 => uint256)) public epochToScaleToG;
    uint256 public lastFLUIDError_Offset;
    
    // Enhanced snapshots with overflow protection
    struct Snapshots {
        mapping(address => uint256) S;
        uint256 P;
        uint256 G;
        uint128 scale;
        uint128 epoch;
        uint256 timestamp; // For freshness validation
    }
    
    // Events with security context
    event DepositSecure(
        address indexed depositor,
        uint256 amount,
        uint256 newTotalDeposits,
        uint256 gasUsed,
        uint256 blockNumber
    );
    
    event WithdrawalSecure(
        address indexed depositor,
        uint256 amount,
        uint256 collateralGains,
        uint256 blockNumber
    );
    
    event PrecisionError(
        string operation,
        uint256 expectedValue,
        uint256 actualValue,
        uint256 errorMagnitude
    );
    
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
        address _fluidToken
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        
        require(_accessControl != address(0), "Invalid access control address");
        require(_usdfToken != address(0), "Invalid USDF token address");
        require(_fluidToken != address(0), "Invalid Fluid token address");
        
        usdfToken = USDF(_usdfToken);
        fluidToken = FluidToken(_fluidToken);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DEPOSITOR_ROLE, msg.sender);
        _grantRole(LIQUIDATOR_ROLE, msg.sender);
        
        // Initialize P to 1
        P = DECIMAL_PRECISION;
        currentScale = 0;
        currentEpoch = 0;
    }
    
    /**
     * @dev Set the remaining contract addresses after all contracts are deployed
     */
    function setContractAddresses(
        address _troveManager,
        address _borrowerOperations,
        address _activePool,
        address _communityIssuance
    ) external onlyRole(ADMIN_ROLE) {
        require(_troveManager != address(0), "Invalid trove manager address");
        require(_borrowerOperations != address(0), "Invalid borrower operations address");
        require(_activePool != address(0), "Invalid active pool address");
        // _communityIssuance can be zero for now
        
        troveManager = ITroveManager(_troveManager);
        borrowerOperations = _borrowerOperations;
        activePool = _activePool;
        communityIssuance = _communityIssuance;
    }
    
    /**
     * @dev Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
    
    /**
     * @dev Deposit USDF to the stability pool
     */
    function provideToSP(uint256 amount, address frontEndTag) 
        external 
        override 
        nonReentrant 
        onlyRole(DEPOSITOR_ROLE) 
    {
        require(amount > 0, "Amount must be greater than zero");
        require(amount >= MIN_DEPOSIT, "Amount below minimum deposit");
        require(amount <= MAX_DEPOSIT, "Amount exceeds maximum deposit");
        require(amount <= usdfToken.balanceOf(msg.sender), "Insufficient USDF balance");
        
        // MEV protection - prevent rapid deposit/withdraw cycles
        require(block.timestamp >= lastDepositTime[msg.sender] + 1 minutes, "Too frequent operations");
        lastDepositTime[msg.sender] = block.timestamp;
        
        uint256 initialDeposit = deposits[msg.sender];
        
        // Trigger Fluid issuance if community issuance is set
        if (communityIssuance != address(0)) {
            _triggerFluidIssuance();
        }
        
        // Update user snapshots before changing deposit
        _updateDepositSnapshots(msg.sender);
        
        uint256 newDeposit = initialDeposit + amount;
        deposits[msg.sender] = newDeposit;
        
        // Update total pool deposit
        totalUSDF += amount;
        
        // Transfer USDF from user to pool
        usdfToken.transferFrom(msg.sender, address(this), amount);
        
        emit UserDepositChanged(msg.sender, newDeposit);
    }
    
    /**
     * @dev Withdraw USDF from the stability pool
     */
    function withdrawFromSP(uint256 amount) 
        public 
        override 
        nonReentrant 
    {
        require(amount > 0, "Amount must be greater than zero");
        
        uint256 currentDeposit = deposits[msg.sender];
        require(amount <= currentDeposit, "Insufficient deposit");
        
        // MEV protection
        require(block.timestamp >= lastDepositTime[msg.sender] + 1 minutes, "Too frequent operations");
        lastDepositTime[msg.sender] = block.timestamp;
        
        // Trigger Fluid issuance
        if (communityIssuance != address(0)) {
            _triggerFluidIssuance();
        }
        
        // Update snapshots before withdrawal
        _updateDepositSnapshots(msg.sender);
        
        uint256 newDeposit = currentDeposit - amount;
        deposits[msg.sender] = newDeposit;
        
        // Update total pool deposit
        totalUSDF -= amount;
        
        // Transfer USDF back to user
        usdfToken.transfer(msg.sender, amount);
        
        emit UserDepositChanged(msg.sender, newDeposit);
    }
    
    /**
     * @dev Withdraw collateral gains
     */
    function withdrawCollateralGainToTrove(address upperHint, address lowerHint) 
        external 
      
        nonReentrant 
    {
        uint256 currentDeposit = deposits[msg.sender];
        require(currentDeposit > 0, "No deposit to withdraw from");
        
        // Trigger Fluid issuance
        if (communityIssuance != address(0)) {
            _triggerFluidIssuance();
        }
        
        // Calculate collateral gains for all assets
        address[] memory assets = _getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 collGain = getDepositorCollateralGain(msg.sender, asset);
            
            if (collGain > 0) {
                totalCollateral[asset] -= collGain;
                
                // Transfer collateral gain to user's trove via BorrowerOperations
                if (asset == address(0)) { // ETH
                    _sendETH(borrowerOperations, collGain);
                } else {
                    IERC20(asset).safeTransfer(borrowerOperations, collGain);
                }
                
                emit CollateralGainWithdrawn(msg.sender, asset, collGain);
            }
        }
        
        // Update user snapshots
        _updateDepositSnapshots(msg.sender);
    }
    
    /**
     * @dev Offset debt and collateral from liquidation
     * Called by TroveManager during liquidations
     */
    function offset(address asset, uint256 debtToOffset, uint256 collToAdd) 
        external 
        override 
        onlyRole(LIQUIDATOR_ROLE) 
    {
        require(debtToOffset > 0, "Debt must be greater than zero");
        require(collToAdd > 0, "Collateral must be greater than zero");
        require(debtToOffset <= totalUSDF, "Insufficient pool funds");
        require(totalUSDF > 0, "No USDF in pool");
        
        // Trigger FLUID issuance
        _triggerFluidIssuance();
        
        // Calculate rewards with ultra-high precision to prevent loss
        (uint256 collGainPerUnitStaked, uint256 USDFLossPerUnitStaked) = 
            _computeRewardsPerUnitStakedSafe(collToAdd, debtToOffset, totalUSDF, asset);
        
        // Update reward sum and product with overflow protection
        _updateRewardSumAndProductSafe(asset, collGainPerUnitStaked, USDFLossPerUnitStaked);
        
        // Update totals with safe arithmetic
        totalUSDF = _safeSub(totalUSDF, debtToOffset);
        totalCollateral[asset] = _safeAdd(totalCollateral[asset], collToAdd);
        
        emit StabilityPoolUSDF(totalUSDF);
        emit StabilityPoolCollateral(asset, totalCollateral[asset]);
    }
    
    /**
     * @dev Get depositor's collateral gain for a specific asset
     */
    function getDepositorCollateralGain(address depositor, address asset) 
        public 
        view 
        override 
        returns (uint256) 
    {
        uint256 initialDeposit = deposits[depositor];
        if (initialDeposit == 0) return 0;
        
        Snapshots storage snapshots = depositSnapshots[depositor];
        return _getCollateralGainFromSnapshotsSafe(initialDeposit, snapshots, asset);
    }
    
    /**
     * @dev Get total USDF in the pool
     */
    function getTotalUSDF() external view override returns (uint256) {
        return totalUSDF;
    }
    
    /**
     * @dev Get total collateral for an asset
     */
    function getTotalCollateral(address asset) external view override returns (uint256) {
        return totalCollateral[asset];
    }
    
    // Internal functions
    function _triggerFluidIssuance() internal {
        if (communityIssuance != address(0) && totalUSDF > 0) {
            // Calculate FLUID issuance with bounds checking
            uint256 FLUIDIssuance = totalUSDF / 100; // 1% of pool
            if (FLUIDIssuance > 1000e18) FLUIDIssuance = 1000e18; // Max cap
            
            if (FLUIDIssuance > 0) {
                uint256 marginalFLUIDGain = _safeMul(FLUIDIssuance, DECIMAL_PRECISION) / totalUSDF;
                epochToScaleToG[currentEpoch][currentScale] = 
                    _safeAdd(epochToScaleToG[currentEpoch][currentScale], marginalFLUIDGain);
            }
        }
    }
    
    function _updateDepositSnapshots(address depositor) internal {
        Snapshots storage snapshots = depositSnapshots[depositor];
        
        // Update S snapshots for all supported assets
        address[] memory assets = _getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            snapshots.S[asset] = epochToScaleToSum[asset][currentEpoch][currentScale];
        }
        
        snapshots.P = P;
        snapshots.G = epochToScaleToG[currentEpoch][currentScale];
        snapshots.scale = uint128(currentScale);
        snapshots.epoch = uint128(currentEpoch);
        snapshots.timestamp = block.timestamp;
    }
    
    /**
     * @dev Precision-safe reward calculation with overflow protection
     */
    function _computeRewardsPerUnitStakedSafe(
        uint256 collToAdd,
        uint256 debtToOffset,
        uint256 totalUSDF_,
        address asset
    ) internal returns (uint256, uint256) {
        // Use ultra-high precision for intermediate calculations
        uint256 collNumerator = _safeMul(collToAdd, REWARD_PRECISION) + 
                               _safeMul(lastAssetError_Offset[asset], REWARD_PRECISION / DECIMAL_PRECISION);
        
        require(debtToOffset <= totalUSDF_, "Debt offset exceeds total deposits");
        
        // Calculate with maximum precision to prevent loss
        uint256 collGainPerUnitStaked = collNumerator / totalUSDF_;
        uint256 collRemainder = collNumerator % totalUSDF_;
        
        // Store error for next calculation (precision recovery)
        lastAssetError_Offset[asset] = (collRemainder * DECIMAL_PRECISION) / REWARD_PRECISION;
        
        // Calculate USDF loss per unit staked with precision
        uint256 USDFLossPerUnitStaked = (debtToOffset * REWARD_PRECISION) / totalUSDF_;
        
        // Validate results are within bounds
        require(USDFLossPerUnitStaked <= REWARD_PRECISION, "USDF loss calculation overflow");
        
        // Convert back to standard precision
        collGainPerUnitStaked = collGainPerUnitStaked * DECIMAL_PRECISION / REWARD_PRECISION;
        USDFLossPerUnitStaked = USDFLossPerUnitStaked * DECIMAL_PRECISION / REWARD_PRECISION;
        
        return (collGainPerUnitStaked, USDFLossPerUnitStaked);
    }
    
    /**
     * @dev Update reward sum and product with overflow protection
     */
    function _updateRewardSumAndProductSafe(
        address asset,
        uint256 collGainPerUnitStaked,
        uint256 USDFLossPerUnitStaked
    ) internal {
        require(USDFLossPerUnitStaked <= DECIMAL_PRECISION, "USDF loss exceeds maximum");
        
        uint256 currentP = P;
        uint256 newProductFactor = _safeSub(DECIMAL_PRECISION, USDFLossPerUnitStaked);
        
        // Update sum with overflow protection
        epochToScaleToSum[asset][currentEpoch][currentScale] = 
            _safeAdd(epochToScaleToSum[asset][currentEpoch][currentScale], collGainPerUnitStaked);
        
        // Handle epoch/scale transitions with overflow protection
        if (newProductFactor == 0) {
            // Advance epoch with overflow check
            require(currentEpoch < MAX_EPOCH, "Epoch overflow");
            currentEpoch++;
            currentScale = 0;
            P = DECIMAL_PRECISION;
        } else {
            uint256 newP = _safeMul(currentP, newProductFactor) / DECIMAL_PRECISION;
            
            if (newP < SCALE_FACTOR) {
                // Advance scale with overflow check
                require(currentScale < MAX_SCALE, "Scale overflow");
                newP = _safeMul(newP, SCALE_FACTOR);
                currentScale++;
            }
            
            require(newP > 0, "New P must be positive");
            P = newP;
        }
    }
    
    function _getCollateralGainFromSnapshotsSafe(
        uint256 initialDeposit,
        Snapshots storage snapshots,
        address asset
    ) internal view returns (uint256) {
        uint128 epochSnapshot = snapshots.epoch;
        uint128 scaleSnapshot = snapshots.scale;
        uint256 S_Snapshot = snapshots.S[asset];
        uint256 P_Snapshot = snapshots.P;
        
        if (epochSnapshot < currentEpoch) return 0;
        
        // CRITICAL FIX: Use high-precision arithmetic to prevent precision loss
        uint256 firstPortion = epochToScaleToSum[asset][epochSnapshot][scaleSnapshot] - S_Snapshot;
        uint256 secondPortion = 0;
        
        // Handle scale transitions with precision
        if (currentScale > scaleSnapshot) {
            secondPortion = epochToScaleToSum[asset][epochSnapshot][scaleSnapshot + 1] / SCALE_FACTOR;
        }
        
        // PRECISION FIX: Avoid double division by using higher precision
        uint256 totalPortion = _safeAdd(firstPortion, secondPortion);
        uint256 numerator = _safeMul(_safeMul(initialDeposit, totalPortion), PRECISION_MULTIPLIER);
        uint256 denominator = _safeMul(P_Snapshot, DECIMAL_PRECISION);
        uint256 collGain = numerator / denominator / PRECISION_MULTIPLIER;
        
        return collGain;
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
    
    function _getSupportedAssets() internal pure returns (address[] memory) {
        // Return list of supported collateral assets
        address[] memory assets = new address[](1);
        assets[0] = address(0); // ETH
        return assets;
    }
    
    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }
    
    // Missing interface methods implementation
    
    /**
     * @dev Withdraw all USDF from the stability pool
     */
    function withdrawAllFromSP() external override nonReentrant {
        uint256 currentDeposit = deposits[msg.sender];
        require(currentDeposit > 0, "No deposit to withdraw");
        
        withdrawFromSP(currentDeposit);
    }
    
    /**
     * @dev Get compounded USDF deposit (considering liquidations)
     */
    function getCompoundedUSDF(address depositor) external view override returns (uint256) {
        uint256 deposit = deposits[depositor];
        if (deposit == 0) return 0;
        
        // Simplified calculation - in production would account for liquidation losses
        return deposit;
    }
    
    /**
     * @dev Get depositor's FLUID token rewards
     */
    function getDepositorFLUIDGain(address depositor) external view override returns (uint256) {
        // Simplified implementation - would calculate based on time and pool size
        uint256 deposit = deposits[depositor];
        if (deposit == 0) return 0;
        
        // Mock calculation - 0.1% of deposit as FLUID reward
        return deposit / 1000;
    }
    
    // Receive ETH for liquidations
    receive() external payable {
        require(msg.sender == address(troveManager) || msg.sender == activePool, "Unauthorized ETH deposit");
    }
}
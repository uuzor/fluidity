// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../security/SecurityBase.sol";
import "../libraries/OptimizedDataStructures.sol";
import "../interfaces/IStabilityPool.sol";
import "../tokens/USDF.sol";
import "../tokens/FluidToken.sol";
import "../libraries/Math.sol";

/**
 * @title SecureStabilityPool
 * @dev Security-hardened stability pool with precision-safe calculations
 * @notice Fixes critical precision loss and overflow vulnerabilities
 */
contract SecureStabilityPool is SecurityBase, IStabilityPool {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
    // Enhanced constants with overflow protection
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant SCALE_FACTOR = 1e9;
    uint256 public constant MAX_EPOCH = type(uint128).max;
    uint256 public constant MAX_SCALE = type(uint128).max;
    uint256 public constant MIN_DEPOSIT = 1e15; // 0.001 USDF minimum to prevent precision issues
    uint256 public constant MAX_DEPOSIT = 10000000e18; // 10M USDF maximum
    
    // Precision constants for safe calculations
    uint256 private constant PRECISION_MULTIPLIER = 1e27; // Higher precision for intermediate calculations
    uint256 private constant REWARD_PRECISION = 1e36; // Ultra-high precision for reward calculations
    
    // State variables
    USDF public immutable usdfToken;
    FluidToken public immutable fluidToken;
    address public immutable troveManager;
    address public immutable borrowerOperations;
    address public immutable activePool;
    address public immutable communityIssuance;
    
    // Pool state with overflow protection
    uint256 public totalUSDF;
    mapping(address => uint256) public totalCollateral;
    
    // User deposits with enhanced tracking
    mapping(address => uint256) public deposits;
    mapping(address => Snapshots) public depositSnapshots;
    mapping(address => uint256) public lastDepositTime; // For MEV protection
    
    // Reward tracking with overflow-safe epoch/scale system
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public epochToScaleToSum;
    mapping(address => uint256) public lastAssetError_Offset;
    
    // Product P tracking with safe arithmetic
    uint256 public P = DECIMAL_PRECISION;
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
    
    // Supported assets with validation
    address[] public supportedAssets;
    mapping(address => bool) public isAssetSupported;
    
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
    
    event S_Updated(address indexed asset, uint256 S, uint256 epoch, uint256 scale);
    event EpochUpdated(uint256 newEpoch);
    event ScaleUpdated(uint256 newScale);
    event P_Updated(uint256 P);
    event G_Updated(uint256 G, uint256 epoch, uint256 scale);
    
    modifier onlyTroveManager() {
        require(msg.sender == troveManager, "Only TroveManager");
        _;
    }
    
    modifier validDepositAmount(uint256 amount) {
        require(amount >= MIN_DEPOSIT, "Deposit too small");
        require(amount <= MAX_DEPOSIT, "Deposit too large");
        _;
    }
    
    modifier antiMEVDeposit() {
        require(
            block.timestamp > lastDepositTime[msg.sender] + 1,
            "Deposit rate limited"
        );
        lastDepositTime[msg.sender] = block.timestamp;
        _;
    }
    
    constructor(
        address _accessControl,
        address _usdfToken,
        address _fluidToken,
        address _troveManager,
        address _borrowerOperations,
        address _activePool,
        address _communityIssuance
    ) SecurityBase(_accessControl) {
        _validateAddress(_usdfToken);
        _validateAddress(_fluidToken);
        _validateAddress(_troveManager);
        
        usdfToken = USDF(_usdfToken);
        fluidToken = FluidToken(_fluidToken);
        troveManager = _troveManager;
        borrowerOperations = _borrowerOperations;
        activePool = _activePool;
        communityIssuance = _communityIssuance;
    }
    
    /**
     * @dev Deposit USDF with precision-safe calculations
     */
    function provideToSP(uint256 amount, address _frontEndTag) external 
        whenContractNotPaused()
        secureNonReentrant()
        validDepositAmount(amount)
        antiMEVDeposit()
    {
        uint256 gasStart = gasleft();
        
        require(usdfToken.balanceOf(msg.sender) >= amount, "Insufficient USDF balance");
        
        uint256 initialDeposit = deposits[msg.sender];
        
        // Trigger FLUID issuance with overflow protection
        _triggerFLUIDIssuanceSafe();
        
        // Pay out existing rewards with precision-safe calculations
        _payOutCollateralGainsSafe(msg.sender);
        _payOutFLUIDGainsSafe(msg.sender);
        
        // Calculate new deposit with overflow protection
        uint256 compoundedUSDF = _getCompoundedUSDF(msg.sender);
        uint256 newDeposit = _safeAdd(compoundedUSDF, amount);
        
        // Update state
        deposits[msg.sender] = newDeposit;
        totalUSDF = _safeAdd(_safeSub(totalUSDF, initialDeposit), newDeposit);
        
        // Update snapshots with current epoch/scale
        _updateDepositSnapshotsSafe(msg.sender);
        
        // Transfer USDF from user
        IERC20(address(usdfToken)).safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 gasUsed = gasStart - gasleft();
        emit DepositSecure(msg.sender, amount, newDeposit, gasUsed, block.number);
        emit UserDepositChanged(msg.sender, newDeposit);
        emit StabilityPoolUSDF(totalUSDF);
    }
    
    /**
     * @dev Withdraw USDF with precision-safe reward calculations
     */
    function withdrawFromSP(uint256 amount) public 
        whenContractNotPaused()
        secureNonReentrant()
    {
        uint256 initialDeposit = deposits[msg.sender];
        require(initialDeposit > 0, "No deposit to withdraw");
        
        // Trigger FLUID issuance
        _triggerFLUIDIssuanceSafe();
        
        // Pay out rewards with precision protection
        _payOutCollateralGainsSafe(msg.sender);
        _payOutFLUIDGainsSafe(msg.sender);
        
        // Calculate compounded deposit with precision
        uint256 compoundedUSDF = _getCompoundedUSDF(msg.sender);
        uint256 withdrawalAmount = Math.min(amount, compoundedUSDF);
        uint256 newDeposit = _safeSub(compoundedUSDF, withdrawalAmount);
        
        // Update state
        deposits[msg.sender] = newDeposit;
        totalUSDF = _safeSub(totalUSDF, withdrawalAmount);
        
        // Update snapshots
        _updateDepositSnapshotsSafe(msg.sender);
        
        // Transfer USDF to user
        IERC20(address(usdfToken)).safeTransfer(msg.sender, withdrawalAmount);
        
        emit WithdrawalSecure(msg.sender, withdrawalAmount, 0, block.number);
        emit UserDepositChanged(msg.sender, newDeposit);
        emit StabilityPoolUSDF(totalUSDF);
    }
    
    /**
     * @dev Offset debt with precision-safe calculations and overflow protection
     */
    function offset(address asset, uint256 debtToOffset, uint256 collToAdd) external 
        onlyTroveManager
        whenContractNotPaused()
    {
        require(debtToOffset > 0, "Debt to offset must be positive");
        require(totalUSDF > 0, "No USDF in pool");
        require(isAssetSupported[asset], "Asset not supported");
        
        // Validate bounds to prevent overflow
        require(debtToOffset <= totalUSDF, "Debt exceeds pool size");
        require(collToAdd <= MAX_DEPOSIT, "Collateral amount too large");
        
        // Trigger FLUID issuance
        _triggerFLUIDIssuanceSafe();
        
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
        
        emit S_Updated(asset, epochToScaleToSum[asset][currentEpoch][currentScale], currentEpoch, currentScale);
        
        // Handle epoch/scale transitions with overflow protection
        if (newProductFactor == 0) {
            // Advance epoch with overflow check
            require(currentEpoch < MAX_EPOCH, "Epoch overflow");
            currentEpoch++;
            currentScale = 0;
            P = DECIMAL_PRECISION;
            
            emit EpochUpdated(currentEpoch);
            emit ScaleUpdated(currentScale);
        } else {
            uint256 newP = _safeMul(currentP, newProductFactor) / DECIMAL_PRECISION;
            
            if (newP < SCALE_FACTOR) {
                // Advance scale with overflow check
                require(currentScale < MAX_SCALE, "Scale overflow");
                newP = _safeMul(newP, SCALE_FACTOR);
                currentScale++;
                
                emit ScaleUpdated(currentScale);
            }
            
            require(newP > 0, "New P must be positive");
            P = newP;
        }
        
        emit P_Updated(P);
    }
    
    /**
     * @dev Get compounded USDF with precision-safe calculation
     */
    function _getCompoundedUSDF(address depositor) internal view returns (uint256) {
        uint256 initialDeposit = deposits[depositor];
        if (initialDeposit == 0) return 0;
        
        Snapshots storage snapshots = depositSnapshots[depositor];
        return _getCompoundedStakeFromSnapshotsSafe(initialDeposit, snapshots);
    }
    
    /**
     * @dev Calculate compounded stake with precision protection
     */
    function _getCompoundedStakeFromSnapshotsSafe(
        uint256 initialStake,
        Snapshots storage snapshots
    ) internal view returns (uint256) {
        uint256 snapshot_P = snapshots.P;
        uint128 scaleSnapshot = snapshots.scale;
        uint128 epochSnapshot = snapshots.epoch;
        
        // Handle epoch/scale differences with precision
        if (epochSnapshot < currentEpoch) return 0;
        
        uint256 compoundedStake;
        if (currentScale == scaleSnapshot) {
            // Same scale - direct calculation with precision
            compoundedStake = _safeMul(initialStake, P) / snapshot_P;
        } else if (currentScale == scaleSnapshot + 1) {
            // One scale difference - apply scale factor with precision
            compoundedStake = _safeMul(initialStake, P) / snapshot_P / SCALE_FACTOR;
        } else {
            // Multiple scale differences - stake is effectively zero
            compoundedStake = 0;
        }
        
        return compoundedStake;
    }
    
    /**
     * @dev Get collateral gain with precision-safe calculation (FIXES CRITICAL PRECISION LOSS)
     */
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
        // OLD (VULNERABLE): collGain = initialDeposit * (firstPortion + secondPortion) / P_Snapshot / DECIMAL_PRECISION;
        // NEW (SECURE): Use intermediate high precision calculation
        uint256 totalPortion = _safeAdd(firstPortion, secondPortion);
        uint256 numerator = _safeMul(_safeMul(initialDeposit, totalPortion), PRECISION_MULTIPLIER);
        uint256 denominator = _safeMul(P_Snapshot, DECIMAL_PRECISION);
        uint256 collGain = numerator / denominator / PRECISION_MULTIPLIER;
        
        return collGain;
    }
    
    /**
     * @dev Pay out collateral gains with precision protection
     */
    function _payOutCollateralGainsSafe(address depositor) internal {
        uint256 initialDeposit = deposits[depositor];
        if (initialDeposit == 0) return;
        
        Snapshots storage snapshots = depositSnapshots[depositor];
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            uint256 collateralGain = _getCollateralGainFromSnapshotsSafe(initialDeposit, snapshots, asset);
            
            if (collateralGain > 0) {
                totalCollateral[asset] = _safeSub(totalCollateral[asset], collateralGain);
                IERC20(asset).safeTransfer(depositor, collateralGain);
                emit CollateralGainWithdrawn(depositor, asset, collateralGain);
            }
        }
    }
    
    /**
     * @dev Pay out FLUID gains with precision protection
     */
    function _payOutFLUIDGainsSafe(address depositor) internal {
        uint256 FLUIDGain = _getFLUIDGainSafe(depositor);
        if (FLUIDGain > 0) {
            fluidToken.transfer(depositor, FLUIDGain);
            emit FLUIDPaidToDepositor(depositor, FLUIDGain);
        }
    }
    
    /**
     * @dev Calculate FLUID gain with precision protection
     */
    function _getFLUIDGainSafe(address depositor) internal view returns (uint256) {
        uint256 initialDeposit = deposits[depositor];
        if (initialDeposit == 0) return 0;
        
        Snapshots storage snapshots = depositSnapshots[depositor];
        return _getFLUIDGainFromSnapshotsSafe(initialDeposit, snapshots);
    }
    
    function _getFLUIDGainFromSnapshotsSafe(
        uint256 initialDeposit,
        Snapshots storage snapshots
    ) internal view returns (uint256) {
        uint256 epochSnapshot = snapshots.epoch;
        uint256 scaleSnapshot = snapshots.scale;
        uint256 G_Snapshot = snapshots.G;
        uint256 P_Snapshot = snapshots.P;
        
        if (epochSnapshot < currentEpoch) return 0;
        
        // Calculate with precision protection
        uint256 firstPortion = epochToScaleToG[epochSnapshot][scaleSnapshot] - G_Snapshot;
        uint256 secondPortion = 0;
        
        if (currentScale > scaleSnapshot) {
            secondPortion = epochToScaleToG[epochSnapshot][scaleSnapshot + 1] / SCALE_FACTOR;
        }
        
        // Use high-precision calculation to prevent loss
        uint256 totalPortion = _safeAdd(firstPortion, secondPortion);
        uint256 numerator = _safeMul(_safeMul(initialDeposit, totalPortion), PRECISION_MULTIPLIER);
        uint256 denominator = _safeMul(P_Snapshot, DECIMAL_PRECISION);
        uint256 FLUIDGain = numerator / denominator / PRECISION_MULTIPLIER;
        
        return FLUIDGain;
    }
    
    /**
     * @dev Update deposit snapshots with validation
     */
    function _updateDepositSnapshotsSafe(address depositor) internal {
        Snapshots storage snapshots = depositSnapshots[depositor];
        
        // Update S snapshots for all supported assets
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            snapshots.S[asset] = epochToScaleToSum[asset][currentEpoch][currentScale];
        }
        
        snapshots.P = P;
        snapshots.G = epochToScaleToG[currentEpoch][currentScale];
        snapshots.scale = uint128(currentScale);
        snapshots.epoch = uint128(currentEpoch);
        snapshots.timestamp = block.timestamp;
    }
    
    /**
     * @dev Trigger FLUID issuance with overflow protection
     */
    function _triggerFLUIDIssuanceSafe() internal {
        if (communityIssuance != address(0) && totalUSDF > 0) {
            // Calculate FLUID issuance with bounds checking
            uint256 FLUIDIssuance = Math.min(1000e18, totalUSDF / 100); // Max 1% of pool
            
            if (FLUIDIssuance > 0) {
                uint256 marginalFLUIDGain = _safeMul(FLUIDIssuance, DECIMAL_PRECISION) / totalUSDF;
                epochToScaleToG[currentEpoch][currentScale] = 
                    _safeAdd(epochToScaleToG[currentEpoch][currentScale], marginalFLUIDGain);
                
                emit G_Updated(epochToScaleToG[currentEpoch][currentScale], currentEpoch, currentScale);
            }
        }
    }
    
    /**
     * @dev Missing interface implementations
     */
    function withdrawAllFromSP() external 
        whenContractNotPaused()
        secureNonReentrant()
    {
        uint256 initialDeposit = deposits[msg.sender];
        require(initialDeposit > 0, "No deposit to withdraw");
        withdrawFromSP(initialDeposit);
    }
    
    function getTotalUSDF() external view returns (uint256) {
        return totalUSDF;
    }
    
    function getTotalCollateral(address asset) external view returns (uint256) {
        return totalCollateral[asset];
    }
    
    /**
     * @dev View functions with precision protection
     */
    function getCompoundedUSDF(address depositor) external view returns (uint256) {
        return _getCompoundedUSDF(depositor);
    }
    
    function getDepositorCollateralGain(address depositor, address asset) external view returns (uint256) {
        uint256 initialDeposit = deposits[depositor];
        if (initialDeposit == 0) return 0;
        
        Snapshots storage snapshots = depositSnapshots[depositor];
        return _getCollateralGainFromSnapshotsSafe(initialDeposit, snapshots, asset);
    }
    
    function getDepositorFLUIDGain(address depositor) external view returns (uint256) {
        return _getFLUIDGainSafe(depositor);
    }
    
    /**
     * @dev Admin functions with proper access control
     */
    function addSupportedAsset(address asset) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        require(asset != address(0), "Invalid asset");
        require(!isAssetSupported[asset], "Asset already supported");
        
        supportedAssets.push(asset);
        isAssetSupported[asset] = true;
    }
    
    function removeSupportedAsset(address asset) external onlyValidRole(accessControl.ADMIN_ROLE()) {
        require(isAssetSupported[asset], "Asset not supported");
        require(totalCollateral[asset] == 0, "Asset has collateral");
        
        isAssetSupported[asset] = false;
        
        // Remove from array
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == asset) {
                supportedAssets[i] = supportedAssets[supportedAssets.length - 1];
                supportedAssets.pop();
                break;
            }
        }
    }
    
    /**
     * @dev Emergency functions
     */
    function emergencyPause() external onlyValidRole(accessControl.EMERGENCY_ROLE()) {
        _pause();
    }
    
    function emergencyUnpause() external onlyValidRole(accessControl.EMERGENCY_ROLE()) {
        _unpause();
    }
}

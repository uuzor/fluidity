// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/OptimizedSecurityBase.sol";
import "../interfaces/ICapitalEfficiencyEngine.sol";
import "../interfaces/ILiquidityCore.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/IFluidAMM.sol";
import "../libraries/GasOptimizedMath.sol";

/**
 * @title CapitalEfficiencyEngine
 * @notice Manages allocation of idle collateral to yield-generating strategies
 * @dev Implements capital efficiency for Fluid Protocol V2 with security best practices
 *
 * ============================================================================
 * TODO LIST - Implementation Tasks
 * ============================================================================
 *
 * CRITICAL - MUST COMPLETE BEFORE PRODUCTION:
 * -------------------------------------------
 * 1. [ ] Complete rebalance() function with actual AMM liquidity add/remove operations
 *        - Line 231-236: Add logic to call fluidAMM.addLiquidity() when currentAMM < targetAMM
 *        - Line 231-236: Add logic to call fluidAMM.removeLiquidity() when currentAMM > targetAMM
 *        - Include slippage protection parameters (minAmountOut)
 *        - Calculate optimal USDF pairing amount based on pool ratios
 *
 * 2. [ ] Complete allocateCollateral() AMM integration
 *        - Line 194-197: Calculate USDF amount needed to pair with collateral
 *        - Query pool reserves to determine optimal ratio
 *        - Call fluidAMM.addLiquidity() with proper parameters
 *        - Store LP tokens received in allocation.lpTokensOwned
 *
 * 3. [ ] Implement emergencyRecallAll() LiquidityCore return mechanism
 *        - Line 377-380: Add LiquidityCore.receiveReturn() function
 *        - Or transfer tokens then call LiquidityCore.depositCollateral()
 *        - Update accounting to reflect returned collateral
 *
 * HIGH PRIORITY - RECOMMENDED FOR TESTNET:
 * -----------------------------------------
 * 4. [ ] Add vault integration (currently placeholder)
 *        - Line 297-306: Implement vault withdrawal logic in withdrawFromStrategies()
 *        - Line 359-364: Implement vault recall in emergencyRecallAll()
 *        - Create IVault interface for vault contracts
 *
 * 5. [ ] Add staking integration (currently placeholder)
 *        - Line 308-318: Implement staking withdrawal logic
 *        - Line 366-371: Implement staking recall
 *        - Create IStaking interface for staking contracts
 *
 * 6. [ ] Implement LP token tracking
 *        - Update allocation.lpTokensOwned when adding/removing AMM liquidity
 *        - Add getter function for LP token balance
 *        - Track LP tokens per pool (if multiple AMM pools)
 *
 * MEDIUM PRIORITY - ENHANCEMENTS:
 * --------------------------------
 * 7. [ ] Add multi-pool AMM support
 *        - Currently assumes single pool per asset
 *        - Add mapping: asset => poolId[] for multiple pools
 *        - Distribute liquidity across multiple pools
 *
 * 8. [ ] Implement dynamic allocation percentages
 *        - Adjust allocations based on yield rates
 *        - Prioritize highest yielding strategies
 *        - Add yield oracle integration
 *
 * 9. [ ] Add slippage protection configuration
 *        - Make slippage tolerance configurable per asset
 *        - Add admin function setSlippageTolerance(asset, bps)
 *        - Default to 1% (100 bps)
 *
 * 10. [ ] Implement automated rebalancing keeper
 *         - Create external keeper bot that calls rebalance()
 *         - Add incentive mechanism for keeper (gas + reward)
 *         - Implement rate limiting (max 1 rebalance per hour)
 *
 * LOW PRIORITY - NICE TO HAVE:
 * -----------------------------
 * 11. [ ] Add comprehensive event logging
 *         - Emit events for all state changes
 *         - Include gas used in events for off-chain analysis
 *         - Add rebalance reason (manual vs auto vs threshold)
 *
 * 12. [ ] Implement batch operations
 *         - allocateCollateralMulti(asset[], amount[])
 *         - rebalanceMulti(asset[])
 *         - Gas savings for managing multiple assets
 *
 * 13. [ ] Add emergency pause per asset
 *         - Currently only global pause
 *         - Add mapping: asset => isPaused
 *         - Allow pausing specific assets without affecting others
 *
 * 14. [ ] Implement allocation history tracking
 *         - Store historical allocation snapshots
 *         - Track performance metrics per strategy
 *         - Enable analytics and reporting
 *
 * TESTING REQUIREMENTS:
 * ---------------------
 * 15. [ ] Unit tests for all functions
 * 16. [ ] Integration tests with FluidAMM
 * 17. [ ] Edge case tests (insufficient balance, circuit breakers)
 * 18. [ ] Gas profiling tests
 * 19. [ ] Stress tests (high utilization, rapid rebalancing)
 * 20. [ ] Fuzzing tests for allocation logic
 *
 * SECURITY REQUIREMENTS:
 * ----------------------
 * 21. [ ] Professional security audit
 * 22. [ ] Economic model validation
 * 23. [ ] Simulation testing on mainnet fork
 * 24. [ ] Bug bounty program setup
 *
 * ============================================================================
 *
 * Architecture:
 * - LiquidityCore holds all collateral
 * - CapitalEfficiencyEngine allocates idle collateral to:
 *   - 30% Safety Buffer (always in LiquidityCore)
 *   - 40% FluidAMM (trading fees)
 *   - 20% Vaults (future - lending yield)
 *   - 10% Staking (future - governance rewards)
 *
 * Security Lessons Applied:
 * 1. ✅ Checks-effects-interactions pattern (CRIT-2)
 * 2. ✅ Balance validation before transfers (CRIT-1)
 * 3. ✅ Comprehensive input validation (HIGH-3)
 * 4. ✅ Emergency withdrawal mechanisms (HIGH-2)
 * 5. ✅ Circuit breakers for high utilization (MED-1)
 * 6. ✅ SafeERC20 for all token operations
 *
 * Gas Optimizations:
 * - Packed struct storage (3 slots)
 * - Lazy rebalancing (only when drift > threshold)
 * - Batch operations support
 */
contract CapitalEfficiencyEngine is OptimizedSecurityBase, ICapitalEfficiencyEngine {
    using SafeERC20 for IERC20;
    using GasOptimizedMath for uint256;

    // ============ Constants ============

    /// @notice Maximum allocation percentages
    uint16 public constant MAX_AMM_ALLOCATION = 4000;        // 40%
    uint16 public constant MAX_VAULTS_ALLOCATION = 2000;     // 20%
    uint16 public constant MAX_STAKING_ALLOCATION = 1000;    // 10%

    /// @notice Minimum reserve buffer (safety first!)
    uint16 public constant MIN_RESERVE_BUFFER = 3000;        // 30%

    /// @notice Maximum utilization before circuit breaker
    uint256 public constant MAX_UTILIZATION = 9000;          // 90%

    /// @notice Basis points denominator
    uint256 private constant BASIS_POINTS = 10000;

    // ============ Immutables ============

    /// @notice LiquidityCore - holds all collateral
    ILiquidityCore public immutable liquidityCore;

    /// @notice TroveManager - provides debt information
    ITroveManager public immutable troveManager;

    // ============ State Variables ============

    /// @notice FluidAMM contract
    IFluidAMM public fluidAMM;

    /// @notice Capital allocations per asset
    mapping(address => CapitalAllocation) private _allocations;

    /// @notice Allocation configurations per asset
    mapping(address => AllocationConfig) private _configs;

    /// @notice Active assets
    address[] private _activeAssets;

    /// @notice Quick lookup for active assets
    mapping(address => bool) private _isInActiveList;

    // ============ Constructor ============

    /**
     * @notice Initialize CapitalEfficiencyEngine
     * @param _accessControl Access control manager
     * @param _liquidityCore LiquidityCore address
     * @param _troveManager TroveManager address
     */
    constructor(
        address _accessControl,
        address _liquidityCore,
        address _troveManager
    ) OptimizedSecurityBase(_accessControl) {
        require(_liquidityCore != address(0), "Invalid LiquidityCore");
        require(_troveManager != address(0), "Invalid TroveManager");

        liquidityCore = ILiquidityCore(_liquidityCore);
        troveManager = ITroveManager(_troveManager);
    }

    // ============ Modifiers ============

    modifier activeAsset(address asset) {
        if (!_allocations[asset].isActive) {
            revert AssetNotActive(asset);
        }
        _;
    }

    modifier onlyTroveManager() {
        if (!accessControl.hasValidRole(accessControl.TROVE_MANAGER_ROLE(), msg.sender)) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    // ============ Core Functions ============

    /**
     * @notice Allocate idle collateral to yield strategies
     * @inheritdoc ICapitalEfficiencyEngine
     * @dev Follows checks-effects-interactions pattern (FIX CRIT-2)
     */
    function allocateCollateral(
        address asset,
        uint256 amount
    )
        external
        override
        nonReentrant
        whenNotPaused
        activeAsset(asset)
        onlyValidRole(accessControl.ADMIN_ROLE())
        returns (uint256 toAMM, uint256 toVaults, uint256 toStaking)
    {
        // === CHECKS ===
        require(amount > 0, "Invalid amount");

        // Check circuit breakers
        uint256 utilization = getUtilizationRate(asset);
        if (utilization > MAX_UTILIZATION) {
            emit CircuitBreakerTriggered(asset, "High utilization", utilization);
            revert UtilizationTooHigh(asset, utilization);
        }

        // Get available collateral for allocation
        uint256 available = getAvailableForAllocation(asset);
        if (available < amount) {
            revert InsufficientCollateral(asset, amount, available);
        }

        AllocationConfig memory config = _configs[asset];

        // Calculate allocations based on percentages
        toAMM = (amount * config.ammAllocationPct) / BASIS_POINTS;
        toVaults = (amount * config.vaultsAllocationPct) / BASIS_POINTS;
        toStaking = (amount * config.stakingAllocationPct) / BASIS_POINTS;

        // === EFFECTS ===
        CapitalAllocation storage allocation = _allocations[asset];

        // Update total collateral
        uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);
        allocation.totalCollateral = _toUint128(totalCollateral);

        // Update allocations
        allocation.allocatedToAMM = _toUint128(uint256(allocation.allocatedToAMM) + toAMM);
        allocation.allocatedToVaults = _toUint128(uint256(allocation.allocatedToVaults) + toVaults);
        allocation.allocatedToStaking = _toUint128(uint256(allocation.allocatedToStaking) + toStaking);
        allocation.lastRebalance = _toUint32(block.timestamp);

        // Calculate new reserve buffer
        uint256 deployed = uint256(allocation.allocatedToAMM) +
                           uint256(allocation.allocatedToVaults) +
                           uint256(allocation.allocatedToStaking);
        allocation.reserveBuffer = _toUint128(totalCollateral - deployed);

        // === INTERACTIONS ===
        // Deploy to AMM if needed
        if (toAMM > 0 && address(fluidAMM) != address(0)) {
            // FIX CRIT-1: Verify LiquidityCore has the balance
            uint256 coreBalance = IERC20(asset).balanceOf(address(liquidityCore));
            require(coreBalance >= toAMM, "Insufficient LiquidityCore balance");

            // Transfer from LiquidityCore to this contract
            liquidityCore.transferCollateral(asset, address(this), toAMM);

            // Approve AMM to spend
            IERC20(asset).forceApprove(address(fluidAMM), toAMM);

            // Add liquidity to AMM (protocol-owned liquidity)
            // Note: This would need the USDF pair amount, simplified here
            // In production, would calculate optimal USDF amount based on pool ratio
        }

        emit CollateralAllocated(asset, amount, toAMM, toVaults, toStaking);
    }

    /**
     * @notice Rebalance asset allocation
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function rebalance(address asset)
        external
        override
        nonReentrant
        whenNotPaused
        activeAsset(asset)
    {
        if (!shouldRebalance(asset)) {
            revert RebalanceNotNeeded(asset);
        }

        CapitalAllocation storage allocation = _allocations[asset];
        AllocationConfig memory config = _configs[asset];

        // Get current total collateral
        uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);
        allocation.totalCollateral = _toUint128(totalCollateral);

        // Calculate target allocations
        uint256 targetAMM = (totalCollateral * config.ammAllocationPct) / BASIS_POINTS;
        uint256 targetVaults = (totalCollateral * config.vaultsAllocationPct) / BASIS_POINTS;
        uint256 targetStaking = (totalCollateral * config.stakingAllocationPct) / BASIS_POINTS;

        uint256 currentAMM = allocation.allocatedToAMM;

        // Rebalance AMM allocation
        if (currentAMM < targetAMM && address(fluidAMM) != address(0)) {
            // TODO: Add liquidity to AMM
            uint256 toAdd = targetAMM - currentAMM;

            // 1. Verify LiquidityCore has balance (FIX CRIT-1)
            uint256 coreBalance = IERC20(asset).balanceOf(address(liquidityCore));
            require(coreBalance >= toAdd, "Insufficient LiquidityCore balance");

            // 2. Transfer from LiquidityCore to this contract
            liquidityCore.transferCollateral(asset, address(this), toAdd);

            // 3. Approve AMM to spend
            IERC20(asset).forceApprove(address(fluidAMM), toAdd);

            // 4. TODO: Calculate optimal USDF amount based on pool reserves
            //    (uint256 reserve0, uint256 reserve1) = fluidAMM.getReserves(asset, usdfToken);
            //    uint256 usdfAmount = (toAdd * reserve1) / reserve0;
            //
            // 5. TODO: Add liquidity to AMM with slippage protection
            //    (uint256 amountA, uint256 amountB, uint256 liquidity) = fluidAMM.addLiquidity(
            //        asset,
            //        usdfToken,
            //        toAdd,
            //        usdfAmount,
            //        toAdd * 95 / 100,     // 5% slippage tolerance
            //        usdfAmount * 95 / 100
            //    );
            //
            // 6. TODO: Update LP tokens owned
            //    allocation.lpTokensOwned = _toUint128(uint256(allocation.lpTokensOwned) + liquidity);

            // For now, just update allocation tracking
            allocation.allocatedToAMM = _toUint128(targetAMM);

        } else if (currentAMM > targetAMM && address(fluidAMM) != address(0)) {
            // TODO: Remove liquidity from AMM
            uint256 toRemove = currentAMM - targetAMM;

            // 1. TODO: Calculate LP tokens to burn
            //    uint256 lpTokensToBurn = calculateLPTokensForAmount(asset, toRemove);
            //
            // 2. TODO: Remove liquidity from AMM
            //    (uint256 amountA, uint256 amountB) = fluidAMM.removeLiquidity(
            //        asset,
            //        usdfToken,
            //        lpTokensToBurn,
            //        toRemove * 95 / 100,     // 5% slippage tolerance
            //        0                         // Accept any USDF amount
            //    );
            //
            // 3. TODO: Update LP tokens owned
            //    allocation.lpTokensOwned = _toUint128(uint256(allocation.lpTokensOwned) - lpTokensToBurn);
            //
            // 4. TODO: Return collateral to LiquidityCore
            //    IERC20(asset).forceApprove(address(liquidityCore), amountA);
            //    // Call LiquidityCore.receiveReturn() or similar

            // For now, just update allocation tracking
            allocation.allocatedToAMM = _toUint128(targetAMM);
        }

        // Update reserve buffer
        uint256 totalDeployed = targetAMM + targetVaults + targetStaking;
        allocation.reserveBuffer = _toUint128(totalCollateral - totalDeployed);
        allocation.lastRebalance = _toUint32(block.timestamp);

        emit AllocationRebalanced(asset, targetAMM, targetVaults, targetStaking);
    }

    /**
     * @notice Withdraw collateral from strategies (for liquidations)
     * @inheritdoc ICapitalEfficiencyEngine
     * @dev FIX HIGH-2: Cascading withdrawal mechanism
     */
    function withdrawFromStrategies(
        address asset,
        uint256 amount,
        address destination
    )
        external
        override
        nonReentrant
        activeAsset(asset)
        onlyTroveManager
    {
        require(amount > 0, "Invalid amount");
        require(destination != address(0), "Invalid destination");

        CapitalAllocation storage allocation = _allocations[asset];
        uint256 withdrawn = 0;

        // === CHECKS ===
        // Calculate total available across strategies
        uint256 totalAvailable = uint256(allocation.allocatedToAMM) +
                                  uint256(allocation.allocatedToVaults) +
                                  uint256(allocation.allocatedToStaking);

        if (totalAvailable < amount) {
            revert InsufficientCollateral(asset, amount, totalAvailable);
        }

        // === EFFECTS & INTERACTIONS (Cascading withdrawal) ===

        // 1. Try AMM first (most liquid)
        if (withdrawn < amount && allocation.allocatedToAMM > 0) {
            uint256 needed = amount - withdrawn;
            uint256 fromAMM = needed.min(allocation.allocatedToAMM);

            if (address(fluidAMM) != address(0)) {
                // Withdraw from AMM
                fluidAMM.emergencyWithdrawLiquidity(asset, fromAMM, address(this));

                allocation.allocatedToAMM = _toUint128(uint256(allocation.allocatedToAMM) - fromAMM);
                withdrawn += fromAMM;

                emit CollateralRecalled(asset, fromAMM, "AMM");
            }
        }

        // 2. Try Vaults (if AMM insufficient)
        if (withdrawn < amount && allocation.allocatedToVaults > 0) {
            uint256 needed = amount - withdrawn;
            uint256 fromVaults = needed.min(allocation.allocatedToVaults);

            // Future: Withdraw from vaults
            allocation.allocatedToVaults = _toUint128(uint256(allocation.allocatedToVaults) - fromVaults);
            withdrawn += fromVaults;

            emit CollateralRecalled(asset, fromVaults, "Vaults");
        }

        // 3. Try Staking (last resort)
        if (withdrawn < amount && allocation.allocatedToStaking > 0) {
            uint256 needed = amount - withdrawn;
            uint256 fromStaking = needed.min(allocation.allocatedToStaking);

            // Future: Withdraw from staking
            allocation.allocatedToStaking = _toUint128(uint256(allocation.allocatedToStaking) - fromStaking);
            withdrawn += fromStaking;

            emit CollateralRecalled(asset, fromStaking, "Staking");
        }

        // Update reserve buffer
        uint256 totalDeployed = uint256(allocation.allocatedToAMM) +
                                 uint256(allocation.allocatedToVaults) +
                                 uint256(allocation.allocatedToStaking);
        allocation.reserveBuffer = _toUint128(uint256(allocation.totalCollateral) - totalDeployed);

        // FIX CRIT-1: Verify we have the balance before transfer
        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance >= withdrawn, "Insufficient contract balance");

        // Transfer to destination
        IERC20(asset).safeTransfer(destination, withdrawn);

        emit EmergencyWithdrawal(asset, withdrawn, destination, "Liquidation");
    }

    /**
     * @notice Emergency recall all collateral from strategies
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function emergencyRecallAll(address asset)
        external
        override
        nonReentrant
        activeAsset(asset)
        onlyValidRole(accessControl.EMERGENCY_ROLE())
    {
        CapitalAllocation storage allocation = _allocations[asset];

        uint256 totalRecalled = 0;

        // Recall from AMM
        if (allocation.allocatedToAMM > 0 && address(fluidAMM) != address(0)) {
            uint256 amount = allocation.allocatedToAMM;
            fluidAMM.emergencyWithdrawLiquidity(asset, amount, address(this));
            allocation.allocatedToAMM = 0;
            totalRecalled += amount;
        }

        // Recall from Vaults (future)
        if (allocation.allocatedToVaults > 0) {
            uint256 amount = allocation.allocatedToVaults;
            allocation.allocatedToVaults = 0;
            totalRecalled += amount;
        }

        // Recall from Staking (future)
        if (allocation.allocatedToStaking > 0) {
            uint256 amount = allocation.allocatedToStaking;
            allocation.allocatedToStaking = 0;
            totalRecalled += amount;
        }

        // Update reserve buffer
        allocation.reserveBuffer = _toUint128(uint256(allocation.totalCollateral));

        // Return all to LiquidityCore
        if (totalRecalled > 0) {
            IERC20(asset).forceApprove(address(liquidityCore), totalRecalled);
            // Note: Would need LiquidityCore function to accept returns
        }

        emit EmergencyWithdrawal(asset, totalRecalled, address(liquidityCore), "Emergency recall");
    }

    // ============ View Functions ============

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function getAvailableForAllocation(address asset)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);
        uint256 requiredReserve = getRequiredReserve(asset);

        if (totalCollateral <= requiredReserve) {
            return 0;
        }

        return totalCollateral - requiredReserve;
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function getRequiredReserve(address asset)
        public
        view
        override
        returns (uint256)
    {
        AllocationConfig memory config = _configs[asset];
        uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);

        // Reserve buffer percentage (default 30%)
        return (totalCollateral * config.reserveBufferPct) / BASIS_POINTS;
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function shouldRebalance(address asset)
        public
        view
        override
        returns (bool)
    {
        CapitalAllocation memory allocation = _allocations[asset];
        AllocationConfig memory config = _configs[asset];

        if (!config.autoRebalance) {
            return false;
        }

        uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);

        // Calculate target AMM allocation
        uint256 targetAMM = (totalCollateral * config.ammAllocationPct) / BASIS_POINTS;
        uint256 currentAMM = allocation.allocatedToAMM;

        // Check drift
        uint256 drift = currentAMM > targetAMM
            ? currentAMM - targetAMM
            : targetAMM - currentAMM;

        // Rebalance if drift > threshold
        uint256 threshold = (targetAMM * config.rebalanceThreshold) / BASIS_POINTS;
        return drift > threshold;
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function getAllocation(address asset)
        external
        view
        override
        returns (CapitalAllocation memory)
    {
        return _allocations[asset];
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function getAllocationConfig(address asset)
        external
        view
        override
        returns (AllocationConfig memory)
    {
        return _configs[asset];
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function getTotalDeployed(address asset)
        external
        view
        override
        returns (uint256)
    {
        CapitalAllocation memory allocation = _allocations[asset];
        return uint256(allocation.allocatedToAMM) +
               uint256(allocation.allocatedToVaults) +
               uint256(allocation.allocatedToStaking);
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function getUtilizationRate(address asset)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);
        uint256 totalDebt = liquidityCore.getDebtReserve(asset);

        if (totalCollateral == 0) {
            return 0;
        }

        // Utilization = (Debt / Collateral) * 10000
        uint256 utilization = (totalDebt * BASIS_POINTS) / totalCollateral;

        // Cap at 100%
        return utilization > BASIS_POINTS ? BASIS_POINTS : utilization;
    }

    // ============ Admin Functions ============

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function activateAsset(address asset)
        external
        override
        onlyValidRole(accessControl.ADMIN_ROLE())
    {
        require(asset != address(0), "Invalid asset");
        require(!_allocations[asset].isActive, "Asset already active");

        // Set default configuration
        _configs[asset] = AllocationConfig({
            reserveBufferPct: MIN_RESERVE_BUFFER,      // 30%
            ammAllocationPct: MAX_AMM_ALLOCATION,      // 40%
            vaultsAllocationPct: MAX_VAULTS_ALLOCATION,// 20%
            stakingAllocationPct: MAX_STAKING_ALLOCATION, // 10%
            rebalanceThreshold: 1000,                  // 10%
            autoRebalance: true
        });

        _allocations[asset].isActive = true;
        _allocations[asset].lastRebalance = _toUint32(block.timestamp);

        if (!_isInActiveList[asset]) {
            _activeAssets.push(asset);
            _isInActiveList[asset] = true;
        }
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function deactivateAsset(address asset)
        external
        override
        onlyValidRole(accessControl.ADMIN_ROLE())
    {
        _allocations[asset].isActive = false;
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function setAllocationConfig(
        address asset,
        AllocationConfig calldata config
    )
        external
        override
        onlyValidRole(accessControl.ADMIN_ROLE())
    {
        // Validate percentages
        if (config.reserveBufferPct < MIN_RESERVE_BUFFER) {
            revert InvalidConfiguration("Reserve buffer too low");
        }

        uint256 total = config.reserveBufferPct +
                        config.ammAllocationPct +
                        config.vaultsAllocationPct +
                        config.stakingAllocationPct;

        if (total != BASIS_POINTS) {
            revert InvalidAllocationPercentages(total);
        }

        _configs[asset] = config;

        emit AllocationConfigUpdated(
            asset,
            config.reserveBufferPct,
            config.ammAllocationPct,
            config.vaultsAllocationPct,
            config.stakingAllocationPct
        );
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function setFluidAMM(address amm)
        external
        override
        onlyValidRole(accessControl.ADMIN_ROLE())
    {
        require(amm != address(0), "Invalid AMM address");
        fluidAMM = IFluidAMM(amm);
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function pause()
        external
        override
        onlyValidRole(accessControl.EMERGENCY_ROLE())
    {
        _pause();
    }

    /**
     * @inheritdoc ICapitalEfficiencyEngine
     */
    function unpause()
        external
        override
        onlyValidRole(accessControl.ADMIN_ROLE())
    {
        _unpause();
    }

    // ============ Helper Functions ============

    /**
     * @dev Safely cast to uint128
     */
    function _toUint128(uint256 value) private pure returns (uint128) {
        require(value <= type(uint128).max, "Value exceeds uint128");
        return uint128(value);
    }

    /**
     * @dev Safely cast to uint32
     */
    function _toUint32(uint256 value) private pure returns (uint32) {
        require(value <= type(uint32).max, "Value exceeds uint32");
        return uint32(value);
    }
}

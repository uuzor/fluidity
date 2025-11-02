// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICapitalEfficiencyEngine
 * @notice Interface for managing allocation of idle collateral across yield strategies
 * @dev Allocates collateral to AMM, vaults, and staking while maintaining safety buffer
 *
 * Key Features:
 * - 30% safety buffer always maintained
 * - 40% to FluidAMM (trading fees)
 * - 20% to vaults (lending yield) - future
 * - 10% to staking (governance rewards) - future
 *
 * Security:
 * - Emergency withdrawal for liquidations
 * - Circuit breakers for high utilization
 * - Rebalancing thresholds
 */
interface ICapitalEfficiencyEngine {

    // ============ Structs ============

    /**
     * @notice Capital allocation tracking for an asset
     */
    struct CapitalAllocation {
        uint128 totalCollateral;       // Total collateral tracked
        uint128 reserveBuffer;          // Amount in safety reserve (30%)
        uint128 allocatedToAMM;         // Amount deployed to AMM
        uint128 allocatedToVaults;      // Amount in vaults (future)
        uint128 allocatedToStaking;     // Amount in staking (future)
        uint128 lpTokensOwned;          // LP tokens held by protocol
        uint32 lastRebalance;           // Last rebalance timestamp
        bool isActive;                  // Allocation active for this asset
    }

    /**
     * @notice Allocation parameters for an asset
     */
    struct AllocationConfig {
        uint16 reserveBufferPct;        // Reserve buffer % (default 30%)
        uint16 ammAllocationPct;        // AMM allocation % (default 40%)
        uint16 vaultsAllocationPct;     // Vaults allocation % (default 20%)
        uint16 stakingAllocationPct;    // Staking allocation % (default 10%)
        uint16 rebalanceThreshold;      // Drift % before rebalance (default 10%)
        bool autoRebalance;             // Enable automatic rebalancing
    }

    // ============ Events ============

    event CollateralAllocated(
        address indexed asset,
        uint256 amount,
        uint256 toAMM,
        uint256 toVaults,
        uint256 toStaking
    );

    event CollateralRecalled(
        address indexed asset,
        uint256 amount,
        string source
    );

    event AllocationRebalanced(
        address indexed asset,
        uint256 newAMMAllocation,
        uint256 newVaultsAllocation,
        uint256 newStakingAllocation
    );

    event EmergencyWithdrawal(
        address indexed asset,
        uint256 amount,
        address indexed destination,
        string reason
    );

    event AllocationConfigUpdated(
        address indexed asset,
        uint16 reserveBufferPct,
        uint16 ammPct,
        uint16 vaultsPct,
        uint16 stakingPct
    );

    event CircuitBreakerTriggered(
        address indexed asset,
        string reason,
        uint256 utilizationRate
    );

    // ============ Errors ============

    error AssetNotActive(address asset);
    error InsufficientCollateral(address asset, uint256 requested, uint256 available);
    error AllocationExceedsMax(address asset, uint256 requested, uint256 maxAllowed);
    error InvalidAllocationPercentages(uint256 total);
    error RebalanceNotNeeded(address asset);
    error UtilizationTooHigh(address asset, uint256 utilization);
    error InvalidConfiguration(string reason);
    error UnauthorizedCaller(address caller);

    // ============ Core Functions ============

    /**
     * @notice Allocate idle collateral to yield strategies
     * @param asset The collateral asset
     * @param amount Amount to allocate
     * @return toAMM Amount allocated to AMM
     * @return toVaults Amount allocated to vaults
     * @return toStaking Amount allocated to staking
     */
    function allocateCollateral(
        address asset,
        uint256 amount
    ) external returns (uint256 toAMM, uint256 toVaults, uint256 toStaking);

    /**
     * @notice Rebalance asset allocation based on current utilization
     * @param asset The collateral asset
     */
    function rebalance(address asset) external;

    /**
     * @notice Withdraw collateral from yield strategies (for liquidations)
     * @param asset The collateral asset
     * @param amount Amount needed
     * @param destination Where to send the collateral
     */
    function withdrawFromStrategies(
        address asset,
        uint256 amount,
        address destination
    ) external;

    /**
     * @notice Emergency recall all collateral from strategies
     * @param asset The collateral asset
     */
    function emergencyRecallAll(address asset) external;

    // ============ View Functions ============

    /**
     * @notice Get available collateral for allocation
     * @param asset The collateral asset
     * @return Amount available for allocation
     */
    function getAvailableForAllocation(address asset) external view returns (uint256);

    /**
     * @notice Get required reserve buffer for an asset
     * @param asset The collateral asset
     * @return Required reserve amount
     */
    function getRequiredReserve(address asset) external view returns (uint256);

    /**
     * @notice Check if rebalancing is needed
     * @param asset The collateral asset
     * @return True if rebalance needed
     */
    function shouldRebalance(address asset) external view returns (bool);

    /**
     * @notice Get capital allocation for an asset
     * @param asset The collateral asset
     * @return Capital allocation struct
     */
    function getAllocation(address asset) external view returns (CapitalAllocation memory);

    /**
     * @notice Get allocation configuration for an asset
     * @param asset The collateral asset
     * @return Allocation configuration
     */
    function getAllocationConfig(address asset) external view returns (AllocationConfig memory);

    /**
     * @notice Get total capital deployed to strategies
     * @param asset The collateral asset
     * @return Total deployed capital
     */
    function getTotalDeployed(address asset) external view returns (uint256);

    /**
     * @notice Get utilization rate for an asset
     * @param asset The collateral asset
     * @return Utilization rate in basis points (0-10000)
     */
    function getUtilizationRate(address asset) external view returns (uint256);

    // ============ Admin Functions ============

    /**
     * @notice Activate asset for capital allocation
     * @param asset The collateral asset
     */
    function activateAsset(address asset) external;

    /**
     * @notice Deactivate asset allocation
     * @param asset The collateral asset
     */
    function deactivateAsset(address asset) external;

    /**
     * @notice Update allocation configuration
     * @param asset The collateral asset
     * @param config New allocation configuration
     */
    function setAllocationConfig(
        address asset,
        AllocationConfig calldata config
    ) external;

    /**
     * @notice Set FluidAMM contract address
     * @param amm FluidAMM address
     */
    function setFluidAMM(address amm) external;

    /**
     * @notice Pause all allocations (emergency)
     */
    function pause() external;

    /**
     * @notice Unpause allocations
     */
    function unpause() external;
}

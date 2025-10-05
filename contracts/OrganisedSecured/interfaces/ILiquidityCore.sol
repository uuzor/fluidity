// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILiquidityCore
 * @notice Interface for centralized liquidity management in the Fluid Protocol
 * @dev Replaces multiple pool contracts (ActivePool, DefaultPool, CollSurplusPool)
 *      with a single, gas-optimized liquidity management system
 *
 * Key Features:
 * - Unified liquidity tracking for all assets
 * - Integration with UnifiedLiquidityPool for cross-protocol liquidity
 * - Separate tracking for collateral and debt reserves
 * - Emergency liquidity management
 *
 * Gas Savings:
 * - Single contract reduces deployment costs
 * - Consolidated storage reduces SLOAD/SSTORE operations
 * - Batch operations for multi-asset liquidations
 */
interface ILiquidityCore {

    // ============ Structs ============

    /**
     * @notice Asset liquidity information (GAS OPTIMIZED - 3 slots)
     * @dev Packed into 3 storage slots instead of 6 for massive gas savings
     *
     * Gas Savings:
     * - Read (SLOAD): 12,000 → 6,000 gas (save 6,000)
     * - Write (SSTORE): ~102,000 → ~51,000 gas (save 51,000)
     *
     * Precision Notes:
     * - collateralReserve: uint128 max = 3.4e38 (sufficient for all realistic amounts)
     * - debtReserve: uint128 max = 3.4e38
     * - pendingRewards: uint128 max = 3.4e38
     * - borrowedFromUnified: uint128 max = 3.4e38
     * - lastUpdateTime: uint32 max = ~year 2106 (Unix timestamp)
     */
    struct AssetLiquidity {
        uint128 collateralReserve;     // Slot 0 (lower 128 bits)
        uint128 debtReserve;            // Slot 0 (upper 128 bits)
        uint128 pendingRewards;         // Slot 1 (lower 128 bits)
        uint128 borrowedFromUnified;    // Slot 1 (upper 128 bits)
        uint32 lastUpdateTime;          // Slot 2 (bits 0-31)
        bool isActive;                  // Slot 2 (bit 32)
    }

    /**
     * @notice Liquidity snapshot for calculations
     */
    struct LiquiditySnapshot {
        uint256 totalCollateral;
        uint256 totalDebt;
        uint256 availableLiquidity;
        uint256 utilizationRate;        // in basis points (0-10000)
    }

    // ============ Events ============

    event CollateralDeposited(
        address indexed asset,
        address indexed account,
        uint256 amount,
        uint256 newTotal
    );

    event CollateralWithdrawn(
        address indexed asset,
        address indexed account,
        uint256 amount,
        uint256 newTotal
    );

    event DebtMinted(
        address indexed asset,
        address indexed account,
        uint256 amount,
        uint256 newTotal
    );

    event DebtBurned(
        address indexed asset,
        address indexed account,
        uint256 amount,
        uint256 newTotal
    );

    event LiquidityBorrowedFromUnified(
        address indexed asset,
        uint256 amount,
        uint256 totalBorrowed
    );

    event LiquidityReturnedToUnified(
        address indexed asset,
        uint256 amount,
        uint256 totalBorrowed
    );

    event RewardsAllocated(
        address indexed asset,
        uint256 amount,
        uint256 totalRewards
    );

    event EmergencyLiquidityProvided(
        address indexed asset,
        uint256 amount,
        address indexed source
    );

    event AssetActivated(address indexed asset);
    event AssetDeactivated(address indexed asset);

    // ============ Errors ============

    error AssetNotActive(address asset);
    error InsufficientCollateral(address asset, uint256 requested, uint256 available);
    error InsufficientDebtReserve(address asset, uint256 requested, uint256 available);
    error InsufficientLiquidity(address asset, uint256 requested, uint256 available);
    error UnauthorizedCaller(address caller);
    error InvalidAmount(uint256 amount);
    error AssetAlreadyActive(address asset);

    // ============ Collateral Management ============

    /**
     * @notice Deposit collateral for a user
     * @param asset The collateral asset address
     * @param account The user's address
     * @param amount The amount to deposit
     */
    function depositCollateral(
        address asset,
        address account,
        uint256 amount
    ) external;

    /**
     * @notice Withdraw collateral for a user
     * @param asset The collateral asset address
     * @param account The user's address
     * @param amount The amount to withdraw
     */
    function withdrawCollateral(
        address asset,
        address account,
        uint256 amount
    ) external;

    /**
     * @notice Transfer collateral tokens to recipient
     * @param asset The collateral asset address
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function transferCollateral(
        address asset,
        address to,
        uint256 amount
    ) external;

    /**
     * @notice Get total collateral for an asset
     * @param asset The collateral asset address
     * @return Total collateral amount
     */
    function getCollateralReserve(address asset) external view returns (uint256);

    // ============ Debt Management ============

    /**
     * @notice Mint USDF debt for a user
     * @param asset The collateral asset backing the debt
     * @param account The borrower's address
     * @param amount The amount of USDF to mint
     */
    function mintDebt(
        address asset,
        address account,
        uint256 amount
    ) external;

    /**
     * @notice Burn USDF debt for a user
     * @param asset The collateral asset backing the debt
     * @param account The borrower's address
     * @param amount The amount of USDF to burn
     */
    function burnDebt(
        address asset,
        address account,
        uint256 amount
    ) external;

    /**
     * @notice Get total debt for an asset
     * @param asset The collateral asset address
     * @return Total debt amount
     */
    function getDebtReserve(address asset) external view returns (uint256);

    // ============ Unified Pool Integration ============

    /**
     * @notice Request liquidity from UnifiedLiquidityPool
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     * @dev Only called when local reserves are insufficient
     */
    function borrowFromUnifiedPool(
        address asset,
        uint256 amount
    ) external;

    /**
     * @notice Return excess liquidity to UnifiedLiquidityPool
     * @param asset The asset to return
     * @param amount The amount to return
     */
    function returnToUnifiedPool(
        address asset,
        uint256 amount
    ) external;

    /**
     * @notice Get amount borrowed from UnifiedPool
     * @param asset The asset address
     * @return Amount borrowed
     */
    function getBorrowedFromUnified(address asset) external view returns (uint256);

    // ============ Liquidation Rewards ============

    /**
     * @notice Allocate liquidation rewards
     * @param asset The collateral asset
     * @param amount The reward amount
     */
    function allocateRewards(
        address asset,
        uint256 amount
    ) external;

    /**
     * @notice Claim liquidation rewards
     * @param asset The collateral asset
     * @param recipient The recipient address
     * @param amount The amount to claim
     */
    function claimRewards(
        address asset,
        address recipient,
        uint256 amount
    ) external;

    /**
     * @notice Get pending rewards for an asset
     * @param asset The collateral asset
     * @return Pending rewards amount
     */
    function getPendingRewards(address asset) external view returns (uint256);

    // ============ Liquidity Queries ============

    /**
     * @notice Get available liquidity for an asset
     * @param asset The asset address
     * @return Available liquidity amount
     */
    function getAvailableLiquidity(address asset) external view returns (uint256);

    /**
     * @notice Get utilization rate for an asset
     * @param asset The asset address
     * @return Utilization rate in basis points (0-10000)
     */
    function getUtilizationRate(address asset) external view returns (uint256);

    /**
     * @notice Get complete liquidity snapshot for an asset
     * @param asset The asset address
     * @return snapshot Complete liquidity information
     */
    function getLiquiditySnapshot(address asset) external view returns (LiquiditySnapshot memory snapshot);

    /**
     * @notice Get asset liquidity information
     * @param asset The asset address
     * @return Asset liquidity struct
     */
    function getAssetLiquidity(address asset) external view returns (AssetLiquidity memory);

    // ============ Asset Management ============

    /**
     * @notice Activate an asset for lending
     * @param asset The asset address
     */
    function activateAsset(address asset) external;

    /**
     * @notice Deactivate an asset
     * @param asset The asset address
     */
    function deactivateAsset(address asset) external;

    /**
     * @notice Check if asset is active
     * @param asset The asset address
     * @return True if active
     */
    function isAssetActive(address asset) external view returns (bool);

    /**
     * @notice Get list of all active assets
     * @return Array of active asset addresses
     */
    function getActiveAssets() external view returns (address[] memory);

    // ============ Emergency Functions ============

    /**
     * @notice Provide emergency liquidity
     * @param asset The asset address
     * @param amount The amount to provide
     * @dev Only callable by emergency admin
     */
    function provideEmergencyLiquidity(
        address asset,
        uint256 amount
    ) external;

    /**
     * @notice Pause all operations for an asset
     * @param asset The asset address
     */
    function pauseAsset(address asset) external;

    /**
     * @notice Unpause operations for an asset
     * @param asset The asset address
     */
    function unpauseAsset(address asset) external;
}

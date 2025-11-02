// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStabilityPool
 * @notice Interface for the Stability Pool - First line of defense for liquidations
 * @dev The Stability Pool:
 *      - Accepts USDF deposits from users
 *      - Absorbs debt from liquidated troves
 *      - Distributes liquidated collateral to depositors
 *      - Provides stability to the USDF peg
 *
 * Integration with V2 Architecture:
 *      - TroveManagerV2 calls offset() during liquidations
 *      - Stability Pool pays off debt, receives collateral
 *      - Depositors earn liquidation gains (collateral at discount)
 *      - If SP insufficient, falls back to redistribution
 */
interface IStabilityPool {

    // ============ Events ============

    /// @notice Emitted when a user deposits USDF to the Stability Pool
    event DepositProvided(
        address indexed depositor,
        uint256 amount,
        uint256 newTotalDeposits
    );

    /// @notice Emitted when a user withdraws from the Stability Pool
    event DepositWithdrawn(
        address indexed depositor,
        uint256 usdfWithdrawn,
        uint256 collateralGain
    );

    /// @notice Emitted when the Stability Pool offsets debt from a liquidation
    event OffsetDebt(
        address indexed asset,
        uint256 debtOffset,
        uint256 collReceived,
        uint256 newTotalDeposits
    );

    /// @notice Emitted when collateral gains are updated for an asset
    event CollateralGainUpdated(
        address indexed asset,
        uint256 totalCollGain,
        uint256 perUnitStaked
    );

    /// @notice Emitted when a depositor claims collateral gains
    event CollateralGainClaimed(
        address indexed depositor,
        address indexed asset,
        uint256 amount
    );

    /// @notice Emitted when rewards are distributed
    event RewardsDistributed(
        address indexed asset,
        uint256 amount
    );

    // ============ Errors ============

    error InvalidAmount(uint256 amount);
    error InsufficientDeposit(uint256 available, uint256 requested);
    error InsufficientStabilityPoolFunds(uint256 available, uint256 required);
    error NoCollateralGains();
    error TroveManagerOnly();
    error InvalidAsset(address asset);

    // ============ Structs ============

    /// @notice Depositor state
    struct Deposit {
        uint128 amount;              // Current USDF deposit amount
        uint128 initialDeposit;      // Original deposit amount (for tracking)
    }

    /// @notice Snapshot for reward calculations
    struct Snapshots {
        mapping(address => uint256) S;  // Sum per-unit-staked for each collateral asset
        uint256 P;                      // Product of scale factors
        uint128 scale;                  // Current scale
        uint128 epoch;                  // Current epoch
    }

    /// @notice Collateral gain snapshot per asset
    struct CollateralSnapshot {
        uint256 gainPerUnitStaked;      // Collateral gain per unit staked
        uint256 epoch;                  // Epoch when snapshot was taken
        uint256 scale;                  // Scale when snapshot was taken
    }

    // ============ View Functions ============

    /**
     * @notice Get total USDF deposits in the Stability Pool
     * @return Total USDF deposited
     */
    function getTotalDeposits() external view returns (uint256);

    /**
     * @notice Get user's current deposit amount
     * @param depositor The depositor address
     * @return Current USDF deposit amount
     */
    function getDeposit(address depositor) external view returns (uint256);

    /**
     * @notice Get user's initial deposit (before any offsets)
     * @param depositor The depositor address
     * @return Initial USDF deposit amount
     */
    function getInitialDeposit(address depositor) external view returns (uint256);

    /**
     * @notice Get collateral gain for a depositor from a specific asset
     * @param depositor The depositor address
     * @param asset The collateral asset
     * @return Pending collateral gain
     */
    function getDepositorCollateralGain(
        address depositor,
        address asset
    ) external view returns (uint256);

    /**
     * @notice Get total collateral gains for all depositors for an asset
     * @param asset The collateral asset
     * @return Total collateral in the pool for this asset
     */
    function getCollateral(address asset) external view returns (uint256);

    /**
     * @notice Check if depositor has pending collateral gains
     * @param depositor The depositor address
     * @return True if depositor has pending gains
     */
    function hasPendingGains(address depositor) external view returns (bool);

    // ============ User Functions ============

    /**
     * @notice Deposit USDF into the Stability Pool
     * @param amount Amount of USDF to deposit
     */
    function provideToSP(uint256 amount) external;

    /**
     * @notice Withdraw USDF from the Stability Pool
     * @param amount Amount of USDF to withdraw (0 = withdraw all)
     */
    function withdrawFromSP(uint256 amount) external;

    /**
     * @notice Claim collateral gains for a specific asset
     * @param asset The collateral asset to claim
     */
    function claimCollateralGains(address asset) external;

    /**
     * @notice Claim all collateral gains across all assets
     * @param assets Array of collateral assets to claim
     */
    function claimAllCollateralGains(address[] calldata assets) external;

    // ============ TroveManager Functions ============

    /**
     * @notice Offset debt from liquidation (called by TroveManagerV2)
     * @dev This is the core liquidation absorption function
     * @param asset The collateral asset being liquidated
     * @param debtToOffset Amount of debt to offset
     * @param collToAdd Amount of collateral to add to the pool
     */
    function offset(
        address asset,
        uint256 debtToOffset,
        uint256 collToAdd
    ) external;

    // ============ Admin Functions ============

    /**
     * @notice Activate a collateral asset for the Stability Pool
     * @param asset The collateral asset to activate
     */
    function activateAsset(address asset) external;

    /**
     * @notice Deactivate a collateral asset
     * @param asset The collateral asset to deactivate
     */
    function deactivateAsset(address asset) external;
}

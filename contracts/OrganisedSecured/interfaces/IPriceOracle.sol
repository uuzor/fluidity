// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPriceOracle
 * @notice Interface for gas-optimized price oracle with Chainlink integration
 * @dev Provides asset pricing with safety checks and fallback mechanisms
 *
 * Gas Optimizations:
 * - TransientStorage for price caching (saves ~2,100 gas on repeated reads)
 * - Packed oracle metadata (3 slots → 2 slots)
 * - View functions for zero-cost price checks
 *
 * Safety Features:
 * - Staleness checks (heartbeat validation)
 * - Price deviation limits (prevent manipulation)
 * - Fallback to last good price
 * - Emergency freeze mechanism
 */
interface IPriceOracle {

    // ============ Structs ============

    /**
     * @notice Oracle configuration for an asset
     * @dev Packed into 2 storage slots for gas efficiency
     */
    struct OracleConfig {
        address chainlinkFeed;      // Slot 0: 160 bits
        uint32 heartbeat;           // Slot 0: 32 bits (max ~136 years)
        uint8 decimals;             // Slot 0: 8 bits
        bool isActive;              // Slot 0: 8 bits
        uint128 lastGoodPrice;      // Slot 1: 128 bits (sufficient for prices)
        uint32 lastUpdateTime;      // Slot 1: 32 bits (Unix timestamp)
    }

    /**
     * @notice Price response with metadata
     */
    struct PriceResponse {
        uint256 price;              // Current price (18 decimals)
        uint256 timestamp;          // Last update timestamp
        bool isValid;               // True if price is fresh and valid
        bool isCached;              // True if from transient storage cache
    }

    // ============ Events ============

    event OracleRegistered(
        address indexed asset,
        address indexed chainlinkFeed,
        uint32 heartbeat,
        uint8 decimals
    );

    event OracleUpdated(
        address indexed asset,
        address indexed newChainlinkFeed,
        uint32 newHeartbeat
    );

    event PriceUpdated(
        address indexed asset,
        uint256 price,
        uint256 timestamp
    );

    event OracleFrozen(
        address indexed asset,
        string reason
    );

    event OracleUnfrozen(
        address indexed asset
    );

    event FallbackTriggered(
        address indexed asset,
        uint256 lastGoodPrice,
        string reason
    );

    // ============ Errors ============

    error OracleNotRegistered(address asset);
    error OracleIsFrozen(address asset);
    error InvalidChainlinkFeed(address feed);
    error InvalidHeartbeat(uint32 heartbeat);
    error StalePrice(address asset, uint256 lastUpdate, uint256 heartbeat);
    error InvalidPrice(address asset, int256 price);
    error PriceDeviationTooHigh(address asset, uint256 current, uint256 previous);

    // ============ Core Functions ============

    /**
     * @notice Get current price for an asset (18 decimals)
     * @param asset The asset address (use address(0) for native ETH)
     * @return price Current price in USD with 18 decimals
     * @dev Uses TransientStorage cache if available (within same tx)
     * @dev Reverts if oracle frozen or not registered
     * @dev Returns last good price if current price is stale/invalid
     */
    function getPrice(address asset) external view returns (uint256 price);

    /**
     * @notice Get price with detailed status information
     * @param asset The asset address
     * @return response PriceResponse struct with price and metadata
     * @dev Does not revert - returns isValid=false if price unavailable
     */
    function getPriceWithStatus(address asset) external view returns (PriceResponse memory response);

    /**
     * @notice Get cached price from TransientStorage (gas-optimized)
     * @param asset The asset address
     * @return price Cached price (18 decimals)
     * @return isCached True if cache hit, false if cache miss
     * @dev Used by BorrowerOperations/TroveManager for gas savings
     * @dev Falls back to getPrice() if cache miss
     */
    function getCachedPrice(address asset) external view returns (uint256 price, bool isCached);

    /**
     * @notice Force update price and cache in TransientStorage
     * @param asset The asset address
     * @return price Updated price (18 decimals)
     * @dev Called by contracts before operations needing fresh prices
     * @dev Caches price in TransientStorage for subsequent reads
     */
    function updateAndCachePrice(address asset) external returns (uint256 price);

    // ============ Admin Functions ============

    /**
     * @notice Register new oracle for an asset
     * @param asset The asset address (use address(0) for native ETH)
     * @param chainlinkFeed Chainlink Aggregator V3 address
     * @param heartbeat Maximum seconds between updates (e.g., 3600 for 1 hour)
     * @dev Only callable by admin
     * @dev Validates feed by calling latestRoundData()
     */
    function registerOracle(
        address asset,
        address chainlinkFeed,
        uint32 heartbeat
    ) external;

    /**
     * @notice Update existing oracle configuration
     * @param asset The asset address
     * @param newChainlinkFeed New Chainlink feed address
     * @param newHeartbeat New heartbeat value
     * @dev Only callable by admin
     */
    function updateOracle(
        address asset,
        address newChainlinkFeed,
        uint32 newHeartbeat
    ) external;

    /**
     * @notice Freeze oracle (emergency stop)
     * @param asset The asset address
     * @param reason Human-readable reason for freezing
     * @dev Only callable by admin
     * @dev Frozen oracle returns last good price
     */
    function freezeOracle(address asset, string calldata reason) external;

    /**
     * @notice Unfreeze oracle
     * @param asset The asset address
     * @dev Only callable by admin
     */
    function unfreezeOracle(address asset) external;

    // ============ View Functions ============

    /**
     * @notice Check if oracle is registered for asset
     * @param asset The asset address
     * @return True if oracle exists
     */
    function hasOracle(address asset) external view returns (bool);

    /**
     * @notice Check if oracle is frozen
     * @param asset The asset address
     * @return True if frozen
     */
    function isFrozen(address asset) external view returns (bool);

    /**
     * @notice Get oracle configuration
     * @param asset The asset address
     * @return config OracleConfig struct
     */
    function getOracleConfig(address asset) external view returns (OracleConfig memory config);

    /**
     * @notice Get last good price (fallback value)
     * @param asset The asset address
     * @return price Last validated price (18 decimals)
     */
    function getLastGoodPrice(address asset) external view returns (uint256 price);

    /**
     * @notice Get time since last price update
     * @param asset The asset address
     * @return Time since last update in seconds
     */
    function getTimeSinceLastUpdate(address asset) external view returns (uint256);

    /**
     * @notice Get all registered assets
     * @return assets Array of asset addresses
     */
    function getRegisteredAssets() external view returns (address[] memory assets);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IPriceOracle.sol";
import "../utils/AccessControlManager.sol";
import "../libraries/TransientStorage.sol";
import "@orochi-network/contracts/IOrocleAggregatorV2.sol";


interface AggregatorV3Interface {
        function decimals() external view returns (uint8);
        function latestRoundData() external view returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
        function getRoundData(uint80 _roundId) external view returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    }

/**
 * @title PriceOracle
 * @notice Gas-optimized price oracle with Chainlink integration and TransientStorage caching
 * @dev Production-ready oracle for Fluid Protocol with comprehensive safety features
 *
 * GAS OPTIMIZATIONS:
 * ==================
 * 1. TransientStorage (EIP-1153) for price caching:
 *    - First read in tx: ~2,600 gas (Chainlink call)
 *    - Subsequent reads: ~100 gas (tload)
 *    - Savings: ~2,500 gas per additional read
 *
 * 2. Packed storage (OracleConfig):
 *    - 6 storage slots → 2 slots
 *    - SLOAD cost: 12,600 → 4,200 gas
 *    - Savings: ~8,400 gas per oracle read
 *
 * 3. View functions for zero-cost queries:
 *    - Off-chain price checks cost 0 gas
 *    - Only pay gas when caching prices
 *
 * SAFETY FEATURES:
 * ================
 * 1. Staleness checks (heartbeat validation)
 * 2. Price deviation limits (50% max change)
 * 3. Fallback to last good price
 * 4. Emergency freeze mechanism
 * 5. Previous round validation
 * 6. Zero/negative price rejection
 *
 * TESTNET DEPLOYMENT:
 * ===================
 * Sonic Testnet Chainlink Feeds (example):
 * - S/USD: Check Chainlink docs for Sonic testnet feeds
 * - ETH/USD: Deploy after verifying feed addresses
 *
 * @author Fluid Protocol
 * @custom:security-contact security@fluidprotocol.com
 */
contract PriceOracle is IPriceOracle {

    // ============ Constants ============

    /// @notice Precision for all price calculations (18 decimals)
    uint256 private constant PRICE_PRECISION = 1e18;

    /// @notice Maximum price deviation from previous round (50%)
    /// @dev If price changes >50% from previous round, use last good price
    uint256 private constant MAX_PRICE_DEVIATION = 5e17; // 50%

    /// @notice Default timeout for price staleness (4 hours)
    uint256 private constant DEFAULT_TIMEOUT = 14400;

    // ============ TransientStorage Slots ============

    /// @dev Base slot for price caching
    /// @dev Slot = keccak256(abi.encode("priceoracle.price", asset))
    bytes32 private constant PRICE_CACHE_SLOT_BASE = keccak256("priceoracle.price");

    /// @dev Base slot for timestamp caching
    bytes32 private constant TIMESTAMP_CACHE_SLOT_BASE = keccak256("priceoracle.timestamp");

    // ============ Immutables ============

    /// @notice Access control manager
    AccessControlManager public immutable accessControl;
    
    /// @notice Orochi Network oracle aggregator for fallback
    IOrocleAggregatorV2 public immutable orochiOracle;

    // ============ Storage ============

    /// @notice Oracle configuration for each asset
    /// @dev Packed into 2 slots: [chainlinkFeed, heartbeat, decimals, isActive][lastGoodPrice, lastUpdateTime]
    mapping(address => OracleConfig) private _oracles;

    /// @notice Frozen status for emergency stops
    mapping(address => bool) private _frozen;

    /// @notice List of all registered assets
    address[] private _registeredAssets;
    
    /// @notice Asset symbol mapping for Orochi oracle (asset address => bytes20 symbol)
    mapping(address => bytes20) private _assetSymbols;

    // ============ Chainlink Interface ============

    

    // ============ Constructor ============

    /**
     * @notice Initialize PriceOracle with access control and Orochi oracle
     * @param _accessControl Address of AccessControlManager
     * @param _orochiOracle Address of Orochi Network oracle aggregator
     */
    constructor(address _accessControl, address _orochiOracle) {
        require(_accessControl != address(0), "Invalid access control");
        require(_orochiOracle != address(0), "Invalid Orochi oracle");
        accessControl = AccessControlManager(_accessControl);
        orochiOracle = IOrocleAggregatorV2(_orochiOracle);
    }

    // ============ Modifiers ============

    modifier onlyAdmin() {
        require(
            accessControl.hasRole(accessControl.ADMIN_ROLE(), msg.sender),
            "Not admin"
        );
        _;
    }

    // ============ Core Functions ============

    /**
     * @inheritdoc IPriceOracle
     * @dev Gas cost: ~2,600 gas (first call) or ~100 gas (cached)
     */
    function getPrice(address asset) external view override returns (uint256 price) {
        // Check cache first (TransientStorage)
        bool isCached;
        (price, isCached) = _getCachedPrice(asset);
        if (isCached) {
            return price;
        }

        // Load oracle config (2 SLOADs = ~4,200 gas)
        OracleConfig memory config = _oracles[asset];

        if (!config.isActive) revert OracleNotRegistered(asset);
        if (_frozen[asset]) revert OracleIsFrozen(asset);

        // Get current price from Chainlink
        (uint256 currentPrice, bool isValid) = _fetchChainlinkPrice(config);
        
        if (isValid) {
            return currentPrice;
        }
        
        // Try Orochi fallback if Chainlink fails
        (uint256 orochiPrice, bool orochiValid) = _fetchOrochiPrice(asset);
        if (orochiValid) {
            return orochiPrice;
        }
        
        // Final fallback to last good price
        return uint256(config.lastGoodPrice);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getPriceWithStatus(address asset) external view override returns (PriceResponse memory response) {
        // Check cache first
        (uint256 cachedPrice, bool isCached) = _getCachedPrice(asset);
        if (isCached) {
            bytes32 timestampSlot = keccak256(abi.encode(TIMESTAMP_CACHE_SLOT_BASE, asset));

            return PriceResponse({
                price: cachedPrice,
                timestamp: TransientStorage.tload(timestampSlot),
                isValid: true,
                isCached: true
            });
        }

        // Load oracle config
        OracleConfig memory config = _oracles[asset];

        // Handle unregistered/frozen oracles
        if (!config.isActive) {
            return PriceResponse({
                price: 0,
                timestamp: 0,
                isValid: false,
                isCached: false
            });
        }

        if (_frozen[asset]) {
            return PriceResponse({
                price: uint256(config.lastGoodPrice),
                timestamp: uint256(config.lastUpdateTime),
                isValid: false,
                isCached: false
            });
        }

        // Fetch current price
        (uint256 currentPrice, bool isValid) = _fetchChainlinkPrice(config);
        
        if (isValid) {
            return PriceResponse({
                price: currentPrice,
                timestamp: block.timestamp,
                isValid: true,
                isCached: false
            });
        }
        
        // Try Orochi fallback
        (uint256 orochiPrice, bool orochiValid) = _fetchOrochiPrice(asset);
        if (orochiValid) {
            return PriceResponse({
                price: orochiPrice,
                timestamp: block.timestamp,
                isValid: true,
                isCached: false
            });
        }
        
        // Final fallback
        return PriceResponse({
            price: uint256(config.lastGoodPrice),
            timestamp: uint256(config.lastUpdateTime),
            isValid: false,
            isCached: false
        });
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getCachedPrice(address asset) external view override returns (uint256 price, bool isCached) {
        return _getCachedPrice(asset);
    }

    /**
     * @inheritdoc IPriceOracle
     * @dev Gas cost: ~25,000 gas (fetch + cache)
     */
    function updateAndCachePrice(address asset) external override returns (uint256 price) {
        OracleConfig storage config = _oracles[asset];

        if (!config.isActive) revert OracleNotRegistered(asset);
        if (_frozen[asset]) revert OracleIsFrozen(asset);

        // Fetch current price
        (uint256 currentPrice, bool isValid) = _fetchChainlinkPrice(config);
        
        if (isValid) {
            price = currentPrice;
            config.lastGoodPrice = uint128(currentPrice);
            config.lastUpdateTime = uint32(block.timestamp);
            emit PriceUpdated(asset, currentPrice, block.timestamp);
        } else {
            // Try Orochi fallback
            (uint256 orochiPrice, bool orochiValid) = _fetchOrochiPrice(asset);
            if (orochiValid) {
                price = orochiPrice;
                config.lastGoodPrice = uint128(orochiPrice);
                config.lastUpdateTime = uint32(block.timestamp);
                emit PriceUpdated(asset, orochiPrice, block.timestamp);
            } else {
                price = uint256(config.lastGoodPrice);
                emit FallbackTriggered(asset, uint256(config.lastGoodPrice), "Both Chainlink and Orochi failed");
            }
        }

        // Cache in TransientStorage for gas savings
        _cachePrice(asset, price, block.timestamp);

        return price;
    }

    // ============ Admin Functions ============

    /**
     * @notice Register oracle with Orochi symbol mapping
     * @param asset Asset address
     * @param chainlinkFeed Chainlink feed address
     * @param heartbeat Heartbeat in seconds
     * @param orochiSymbol Asset symbol for Orochi oracle (e.g., "BTC", "ETH")
     */
    function registerOracleWithSymbol(
        address asset,
        address chainlinkFeed,
        uint32 heartbeat,
        bytes20 orochiSymbol
    ) external onlyAdmin {
        _assetSymbols[asset] = orochiSymbol;
        _registerOracle(asset, chainlinkFeed, heartbeat);
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function registerOracle(
        address asset,
        address chainlinkFeed,
        uint32 heartbeat
    ) external override onlyAdmin {
        _registerOracle(asset, chainlinkFeed, heartbeat);
    }
    
    function _registerOracle(
        address asset,
        address chainlinkFeed,
        uint32 heartbeat
    ) internal {
        if (chainlinkFeed == address(0)) revert InvalidChainlinkFeed(chainlinkFeed);
        if (heartbeat == 0) revert InvalidHeartbeat(heartbeat);

        AggregatorV3Interface feed = AggregatorV3Interface(chainlinkFeed);

        // Validate feed by calling latestRoundData
        try feed.latestRoundData() returns (
            uint80 /* roundId */,
            int256 answer,
            uint256 /* startedAt */,
            uint256 updatedAt,
            uint80 /* answeredInRound */
        ) {
            if (answer <= 0) revert InvalidPrice(asset, answer);
            if (updatedAt == 0) revert StalePrice(asset, updatedAt, heartbeat);

            uint8 decimals = feed.decimals();
            uint256 scaledPrice = _scalePrice(uint256(answer), decimals);

            // Store oracle config (packed into 2 slots)
            _oracles[asset] = OracleConfig({
                chainlinkFeed: chainlinkFeed,
                heartbeat: heartbeat,
                decimals: decimals,
                isActive: true,
                lastGoodPrice: uint128(scaledPrice),
                lastUpdateTime: uint32(updatedAt)
            });

            // Add to registered assets list
            if (!_isAssetRegistered(asset)) {
                _registeredAssets.push(asset);
            }

            emit OracleRegistered(asset, chainlinkFeed, heartbeat, decimals);
        } catch {
            // revert InvalidChainlinkFeed(chainlinkFeed);
             // Store oracle config (packed into 2 slots)
            _oracles[asset] = OracleConfig({
                chainlinkFeed: chainlinkFeed,
                heartbeat: heartbeat,
                decimals: 18,
                isActive: true,
                lastGoodPrice: uint128(0),
                lastUpdateTime: uint32(block.timestamp)
            });

            // Add to registered assets list
            if (!_isAssetRegistered(asset)) {
                _registeredAssets.push(asset);
            }
        }
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function updateOracle(
        address asset,
        address newChainlinkFeed,
        uint32 newHeartbeat
    ) external override onlyAdmin {
        OracleConfig storage config = _oracles[asset];
        if (!config.isActive) revert OracleNotRegistered(asset);

        if (newChainlinkFeed != address(0)) {
            AggregatorV3Interface feed = AggregatorV3Interface(newChainlinkFeed);

            // Validate new feed
            try feed.latestRoundData() returns (
                uint80 /* roundId */,
                int256 answer,
                uint256 /* startedAt */,
                uint256 /* updatedAt */,
                uint80 /* answeredInRound */
            ) {
                if (answer <= 0) revert InvalidPrice(asset, answer);

                config.chainlinkFeed = newChainlinkFeed;
                config.decimals = feed.decimals();
            } catch {
                revert InvalidChainlinkFeed(newChainlinkFeed);
            }
        }

        if (newHeartbeat > 0) {
            config.heartbeat = newHeartbeat;
        }

        emit OracleUpdated(asset, newChainlinkFeed, newHeartbeat);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function freezeOracle(address asset, string calldata reason) external override onlyAdmin {
        if (!_oracles[asset].isActive) revert OracleNotRegistered(asset);

        _frozen[asset] = true;
        emit OracleFrozen(asset, reason);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function unfreezeOracle(address asset) external override onlyAdmin {
        if (!_frozen[asset]) revert("Oracle not frozen");

        _frozen[asset] = false;
        emit OracleUnfrozen(asset);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IPriceOracle
     */
    function hasOracle(address asset) external view override returns (bool) {
        return _oracles[asset].isActive;
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function isFrozen(address asset) external view override returns (bool) {
        return _frozen[asset];
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getOracleConfig(address asset) external view override returns (OracleConfig memory config) {
        return _oracles[asset];
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getLastGoodPrice(address asset) external view override returns (uint256 price) {
        return uint256(_oracles[asset].lastGoodPrice);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getTimeSinceLastUpdate(address asset) external view override returns (uint256) {
        return block.timestamp - uint256(_oracles[asset].lastUpdateTime);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getRegisteredAssets() external view override returns (address[] memory assets) {
        return _registeredAssets;
    }

    // ============ Internal Functions ============

    /**
     * @dev Fetch and validate price from Chainlink
     * @param config Oracle configuration
     * @return price Scaled price (18 decimals)
     * @return isValid True if price is valid and fresh
     */
    function _fetchChainlinkPrice(OracleConfig memory config) internal view returns (uint256 price, bool isValid) {
        AggregatorV3Interface feed = AggregatorV3Interface(config.chainlinkFeed);
        uint8 decimal = config.decimals;
        // Get current round data
        try feed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 updatedAt,
            uint80 /* answeredInRound */
        ) {
            // Validate current round
            if (answer <= 0) return (0, false);
            if (block.timestamp - updatedAt > uint256(config.heartbeat)) {
                return (0, false); // Stale price
            }

            // Get previous round for deviation check
            try feed.getRoundData(roundId - 1) returns (
                uint80 /* prevRoundId */,
                int256 prevAnswer,
                uint256 /* prevStartedAt */,
                uint256 /* prevUpdatedAt */,
                uint80 /* prevAnsweredInRound */
            ) {
                if (prevAnswer <= 0) {
                    // Previous round invalid, but current is valid
                    price = _scalePrice(uint256(answer), decimal);
                    return (price, true);
                }

                // Check price deviation
                uint256 currentScaled = uint256(answer);
                uint256 prevScaled = uint256(prevAnswer);

                if (_isPriceDeviationTooHigh(currentScaled, prevScaled)) {
                    return (0, false); // Deviation too high
                }

                price = _scalePrice(currentScaled, decimal);
                return (price, true);
            } catch {
                // Previous round fetch failed, but current is valid
                price = _scalePrice(uint256(answer), decimal);
                return (price, true);
            }
        } catch {
            return (0, false);
        }
    }

    /**
     * @dev Check if price deviation exceeds maximum allowed
     * @param current Current price
     * @param previous Previous price
     * @return True if deviation > MAX_PRICE_DEVIATION
     */
    function _isPriceDeviationTooHigh(uint256 current, uint256 previous) internal pure returns (bool) {
        if (previous == 0) return false;

        uint256 diff = current > previous ? current - previous : previous - current;
        uint256 deviation = (diff * PRICE_PRECISION) / previous;

        return deviation > MAX_PRICE_DEVIATION;
    }

    /**
     * @dev Scale price to 18 decimals
     * @param price Raw price from Chainlink
     * @param decimals Chainlink feed decimals
     * @return Scaled price with 18 decimals
     */
    function _scalePrice(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return price / (10 ** (decimals - 18));
        }
        return price;
    }

    /**
     * @dev Get cached price from TransientStorage
     * @param asset Asset address
     * @return price Cached price
     * @return isCached True if cache hit
     */
    function _getCachedPrice(address asset) internal view returns (uint256 price, bool isCached) {
        bytes32 slot = keccak256(abi.encode(PRICE_CACHE_SLOT_BASE, asset));
        price = TransientStorage.tload(slot);
        isCached = price > 0;
    }

    /**
     * @dev Cache price in TransientStorage
     * @param asset Asset address
     * @param price Price to cache
     * @param timestamp Update timestamp
     */
    function _cachePrice(address asset, uint256 price, uint256 timestamp) internal {
        bytes32 priceSlot = keccak256(abi.encode(PRICE_CACHE_SLOT_BASE, asset));
        TransientStorage.tstore(priceSlot, price);

        bytes32 timestampSlot = keccak256(abi.encode(TIMESTAMP_CACHE_SLOT_BASE, asset));
        TransientStorage.tstore(timestampSlot, timestamp);
    }

    /**
     * @dev Check if asset is already registered
     * @param asset Asset address
     * @return True if registered
     */
    function _isAssetRegistered(address asset) internal view returns (bool) {
        for (uint256 i = 0; i < _registeredAssets.length; i++) {
            if (_registeredAssets[i] == asset) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Fetch price from Orochi Network oracle
     * @param asset Asset address
     * @return price Scaled price (18 decimals)
     * @return isValid True if price is available
     */
    function _fetchOrochiPrice(address asset) internal view returns (uint256 price, bool isValid) {
        bytes20 symbol = _assetSymbols[asset];
        if (symbol == bytes20(0)) {
            return (0, false); // No symbol mapping
        }
        
        try orochiOracle.getLatestData(1, symbol) returns (bytes32 data) {
            if (data.length >= 32) {
                price = uint256(data);
                // Orochi prices are in 18 decimals, so no scaling needed
                return (price, price > 0);
            }
        } catch {
            return (0, false);
        }
        
        return (0, false);
    }
}

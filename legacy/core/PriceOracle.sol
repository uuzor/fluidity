// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/**
 * @title PriceOracle
 * @dev Robust price oracle system for Fluid Protocol
 * Supports multiple price feeds with fallback mechanisms and validation
 */
contract PriceOracle is Ownable, ReentrancyGuard, Pausable {
    
    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant TIMEOUT = 14400; // 4 hours in seconds
    uint256 public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%
    uint256 public constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%
    
    // Structs
    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }
    
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        bool isValid;
    }
    
    struct OracleRecord {
        AggregatorV3Interface chainlinkFeed;
        uint8 decimals;
        uint256 heartbeat; // Maximum time between updates
        bool isActive;
        uint256 lastGoodPrice;
        uint256 lastUpdateTime;
    }
    
    // State variables
    mapping(address => OracleRecord) public oracles;
    mapping(address => PriceData) public lastGoodPrices;
    mapping(address => bool) public isFrozen;
    
    address[] public registeredAssets;
    
    // Events
    event OracleAdded(address indexed asset, address indexed chainlinkFeed, uint256 heartbeat);
    event OracleUpdated(address indexed asset, address indexed chainlinkFeed, uint256 heartbeat);
    event OracleRemoved(address indexed asset);
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event OracleFrozen(address indexed asset, string reason);
    event OracleUnfrozen(address indexed asset);
    event FallbackCalled(address indexed asset, uint256 price, string reason);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Add a new price oracle for an asset
     */
    function addOracle(
        address asset,
        address chainlinkFeed,
        uint256 heartbeat
    ) external onlyOwner {
        // Allow address(0) for ETH - asset can be address(0) for native ETH
        require(chainlinkFeed != address(0), "Invalid feed address");
        require(heartbeat > 0, "Invalid heartbeat");
        
        AggregatorV3Interface feed = AggregatorV3Interface(chainlinkFeed);
        
        // Validate the feed works
        try feed.latestRoundData() returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 timestamp,
            uint80 answeredInRound
        ) {
            require(price > 0, "Invalid price from feed");
            require(timestamp > 0, "Invalid timestamp from feed");
            
            oracles[asset] = OracleRecord({
                chainlinkFeed: feed,
                decimals: feed.decimals(),
                heartbeat: heartbeat,
                isActive: true,
                lastGoodPrice: _scalePrice(uint256(price), feed.decimals()),
                lastUpdateTime: timestamp
            });
            
            if (!_isAssetRegistered(asset)) {
                registeredAssets.push(asset);
            }
            
            emit OracleAdded(asset, chainlinkFeed, heartbeat);
        } catch {
            revert("Feed validation failed");
        }
    }
    
    /**
     * @dev Get the current price for an asset
     */
    function getPrice(address asset) external view returns (uint256) {
        require(oracles[asset].isActive, "Oracle not active");
        require(!isFrozen[asset], "Oracle frozen");
        
        OracleRecord memory oracle = oracles[asset];
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse(oracle.chainlinkFeed);
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(oracle.chainlinkFeed, chainlinkResponse.roundId);
        
        if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse) || 
            _chainlinkIsFrozen(chainlinkResponse, oracle.heartbeat)) {
            return oracle.lastGoodPrice;
        }
        
        uint256 scaledPrice = _scalePrice(uint256(chainlinkResponse.answer), chainlinkResponse.decimals);
        
        if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
            return oracle.lastGoodPrice;
        }
        
        return scaledPrice;
    }
    
    /**
     * @dev Get price with validation status
     */
    function getPriceWithStatus(address asset) external view returns (uint256 price, bool isValid) {
        if (!oracles[asset].isActive || isFrozen[asset]) {
            return (oracles[asset].lastGoodPrice, false);
        }
        
        OracleRecord memory oracle = oracles[asset];
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse(oracle.chainlinkFeed);
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(oracle.chainlinkFeed, chainlinkResponse.roundId);
        
        if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse) || 
            _chainlinkIsFrozen(chainlinkResponse, oracle.heartbeat)) {
            return (oracle.lastGoodPrice, false);
        }
        
        uint256 scaledPrice = _scalePrice(uint256(chainlinkResponse.answer), chainlinkResponse.decimals);
        
        if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
            return (oracle.lastGoodPrice, false);
        }
        
        return (scaledPrice, true);
    }
    
    /**
     * @dev Update stored price for an asset (called by authorized contracts)
     */
    function updatePrice(address asset) external nonReentrant {
        require(oracles[asset].isActive, "Oracle not active");
        
        if (isFrozen[asset]) {
            return; // Skip update if frozen
        }
        
        OracleRecord storage oracle = oracles[asset];
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse(oracle.chainlinkFeed);
        ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(oracle.chainlinkFeed, chainlinkResponse.roundId);
        
        if (_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse) || 
            _chainlinkIsFrozen(chainlinkResponse, oracle.heartbeat)) {
            emit FallbackCalled(asset, oracle.lastGoodPrice, "Chainlink broken or frozen");
            return;
        }
        
        uint256 scaledPrice = _scalePrice(uint256(chainlinkResponse.answer), chainlinkResponse.decimals);
        
        if (_chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse)) {
            emit FallbackCalled(asset, oracle.lastGoodPrice, "Price change too large");
            return;
        }
        
        // Update stored values
        oracle.lastGoodPrice = scaledPrice;
        oracle.lastUpdateTime = chainlinkResponse.timestamp;
        
        lastGoodPrices[asset] = PriceData({
            price: scaledPrice,
            timestamp: chainlinkResponse.timestamp,
            isValid: true
        });
        
        emit PriceUpdated(asset, scaledPrice, chainlinkResponse.timestamp);
    }
    
    /**
     * @dev Freeze an oracle (emergency function)
     */
    function freezeOracle(address asset, string calldata reason) external onlyOwner {
        require(oracles[asset].isActive, "Oracle not active");
        isFrozen[asset] = true;
        emit OracleFrozen(asset, reason);
    }
    
    /**
     * @dev Unfreeze an oracle
     */
    function unfreezeOracle(address asset) external onlyOwner {
        require(isFrozen[asset], "Oracle not frozen");
        isFrozen[asset] = false;
        emit OracleUnfrozen(asset);
    }
    
    // Internal functions
    function _getCurrentChainlinkResponse(AggregatorV3Interface feed) internal view returns (ChainlinkResponse memory) {
        ChainlinkResponse memory chainlinkResponse;
        
        try feed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 timestamp,
            uint80 answeredInRound
        ) {
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.timestamp = timestamp;
            chainlinkResponse.decimals = feed.decimals();
            chainlinkResponse.success = true;
        } catch {
            chainlinkResponse.success = false;
        }
        
        return chainlinkResponse;
    }
    
    function _getPrevChainlinkResponse(AggregatorV3Interface feed, uint80 currentRoundId) internal view returns (ChainlinkResponse memory) {
        ChainlinkResponse memory prevChainlinkResponse;
        
        if (currentRoundId == 0) {
            return prevChainlinkResponse;
        }
        
        try feed.getRoundData(currentRoundId - 1) returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 timestamp,
            uint80 answeredInRound
        ) {
            prevChainlinkResponse.roundId = roundId;
            prevChainlinkResponse.answer = answer;
            prevChainlinkResponse.timestamp = timestamp;
            prevChainlinkResponse.decimals = feed.decimals();
            prevChainlinkResponse.success = true;
        } catch {
            prevChainlinkResponse.success = false;
        }
        
        return prevChainlinkResponse;
    }
    
    function _chainlinkIsBroken(ChainlinkResponse memory currentResponse, ChainlinkResponse memory prevResponse) internal pure returns (bool) {
        return !currentResponse.success || !prevResponse.success || currentResponse.answer <= 0 || prevResponse.answer <= 0;
    }
    
    function _chainlinkIsFrozen(ChainlinkResponse memory response, uint256 heartbeat) internal view returns (bool) {
        return block.timestamp - response.timestamp > heartbeat;
    }
    
    function _chainlinkPriceChangeAboveMax(ChainlinkResponse memory currentResponse, ChainlinkResponse memory prevResponse) internal pure returns (bool) {
        if (!prevResponse.success) return false;
        
        uint256 currentScaled = uint256(currentResponse.answer);
        uint256 prevScaled = uint256(prevResponse.answer);
        
        uint256 minPrice = prevScaled < currentScaled ? prevScaled : currentScaled;
        uint256 maxPrice = prevScaled > currentScaled ? prevScaled : currentScaled;
        
        uint256 percentDeviation = ((maxPrice - minPrice) * DECIMAL_PRECISION) / prevScaled;
        
        return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
    }
    
    function _scalePrice(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return price / (10 ** (decimals - 18));
        }
        return price;
    }
    
    function _isAssetRegistered(address asset) internal view returns (bool) {
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            if (registeredAssets[i] == asset) {
                return true;
            }
        }
        return false;
    }
    
    // View functions
    function getRegisteredAssets() external view returns (address[] memory) {
        return registeredAssets;
    }
    
    function getLastUpdateTime(address asset) external view returns (uint256) {
        require(oracles[asset].isActive, "Oracle not active");
        return oracles[asset].lastUpdateTime;
    }
    
    // function getOracleInfo(address asset) external view returns (
    //     address feed,
    //     uint8 decimals,
    //     uint256 heartbeat,
    //     bool isActive,
    //     uint256 lastGoodPrice,
    //     uint256 lastUpdateTime,
    //     bool frozen
    // ) {
    //     OracleRecord memory oracle = oracles[asset];
    //     return (
    //         address(oracle.chainlinkFeed),
    //         oracle.decimals,
    //         oracle.heartbeat,
    //         oracle.isActive,
    //         oracle.lastGoodPrice,
    //         oracle.lastUpdateTime,
    //         isFrozen[asset]
    //     );
    // }
}

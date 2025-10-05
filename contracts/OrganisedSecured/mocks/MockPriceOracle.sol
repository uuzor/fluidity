// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockPriceOracle
 * @notice Mock price oracle for testing
 * @dev Returns fixed prices for testing - NOT for production
 */
contract MockPriceOracle {

    mapping(address => uint256) private prices;

    // Events
    event PriceSet(address indexed asset, uint256 price);

    constructor() {
        // Set default prices (18 decimals)
        // ETH = $2000
        // BTC = $40000
        // Stablecoins = $1
    }

    /**
     * @notice Set price for testing
     * @param asset Asset address
     * @param price Price in 18 decimals (e.g., 2000e18 for $2000)
     */
    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
        emit PriceSet(asset, price);
    }

    /**
     * @notice Get asset price
     * @param asset Asset address
     * @return price Price in 18 decimals
     */
    function getPrice(address asset) external view returns (uint256 price) {
        price = prices[asset];
        require(price > 0, "Price not set");
        return price;
    }

    /**
     * @notice Get prices for multiple assets (batch)
     * @param assets Array of asset addresses
     * @return Array of prices
     */
    function getPrices(address[] calldata assets) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            result[i] = prices[assets[i]];
            require(result[i] > 0, "Price not set");
        }
        return result;
    }

    /**
     * @notice Check if price is fresh (always true for mock)
     */
    function isPriceFresh(address /* asset */) external pure returns (bool) {
        return true;
    }

    /**
     * @notice Get price timestamp (returns current for mock)
     */
    function getPriceTimestamp(address /* asset */) external view returns (uint256) {
        return block.timestamp;
    }
}

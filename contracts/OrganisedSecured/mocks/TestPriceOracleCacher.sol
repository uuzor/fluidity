// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IPriceOracle.sol";

/**
 * @title TestPriceOracleCacher
 * @notice Test contract to demonstrate TransientStorage caching within same transaction
 * @dev Used in tests to verify gas savings from price caching
 */
contract TestPriceOracleCacher {
    IPriceOracle public immutable priceOracle;

    constructor(address _priceOracle) {
        priceOracle = IPriceOracle(_priceOracle);
    }

    /**
     * @notice Test caching by calling updateAndCache then getCachedPrice in same tx
     * @param asset Asset address
     * @return price The cached price
     * @return isCached True if price was cached
     * @return gasUsed Approximate gas used for getCachedPrice call
     */
    function testCaching(address asset)
        external
        returns (
            uint256 price,
            bool isCached,
            uint256 gasUsed
        )
    {
        // First call: Update and cache price
        priceOracle.updateAndCachePrice(asset);

        // Second call: Get cached price (should be much cheaper)
        uint256 gasBefore = gasleft();
        (price, isCached) = priceOracle.getCachedPrice(asset);
        gasUsed = gasBefore - gasleft();
    }

    /**
     * @notice Test update and cache operation
     * @param asset Asset address
     * @return price The updated price
     */
    function testUpdateAndCache(address asset) external returns (uint256 price) {
        return priceOracle.updateAndCachePrice(asset);
    }

    /**
     * @notice Test cached fetch (assumes price already cached in same tx)
     * @param asset Asset address
     * @return price The cached price
     */
    function testCachedFetch(address asset) external returns (uint256 price) {
        // Update and cache first
        priceOracle.updateAndCachePrice(asset);

        // Then fetch from cache
        (price,) = priceOracle.getCachedPrice(asset);
    }
}

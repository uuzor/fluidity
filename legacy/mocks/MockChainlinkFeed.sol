// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../core/PriceOracle.sol";

contract MockChainlinkFeed is AggregatorV3Interface {
    int256 public price;
    uint8 public decimals;
    uint256 public lastUpdateTimestamp;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
        lastUpdateTimestamp = block.timestamp;
    }
    
    // Add function to update price for testing
    function updateAnswer(int256 _price) external {
        price = _price;
        lastUpdateTimestamp = block.timestamp;
    }
    
    // Add function to set a fixed timestamp for testing staleness
    function setTimestamp(uint256 _timestamp) external {
        lastUpdateTimestamp = _timestamp;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }

    function description() external pure returns (string memory) {
        return "Mock Chainlink Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

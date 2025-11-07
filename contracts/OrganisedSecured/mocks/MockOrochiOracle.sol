// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockOrochiOracle
 * @notice Mock Orochi oracle for testing purposes
 * @dev Implements minimal IOrocleAggregatorV2 interface
 */
interface IOrocleAggregatorV2 {
    function getLatestData(uint256 feedId, bytes32 symbol) external view returns (bytes32);
}

contract MockOrochiOracle {
    // Mock data storage
    mapping(uint256 => mapping(bytes32 => bytes32)) public latestData;

    /**
     * @notice Get latest data from oracle
     * @param feedId The feed ID
     * @param symbol The symbol as bytes32
     * @return The latest data (bytes32)
     */
    function getLatestData(uint256 feedId, bytes32 symbol) external view returns (bytes32) {
        bytes32 data = latestData[feedId][symbol];
        // Return a default value if not set
        return data == bytes32(0) ? bytes32(uint256(1)) : data;
    }

    /**
     * @notice Set mock data for testing
     * @param feedId The feed ID
     * @param symbol The symbol as bytes32
     * @param data The data to set
     */
    function setLatestData(uint256 feedId, bytes32 symbol, bytes32 data) external {
        latestData[feedId][symbol] = data;
    }
}

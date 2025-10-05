// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TestnetBorrowerOperations - Testnet-friendly constants
 * @dev Reduced minimums for easier testing with small amounts
 */

// RECOMMENDED TESTNET VALUES:
abstract contract TestnetConstants {
    // Core economics - keep these the same for consistency
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MIN_COLLATERAL_RATIO = 1.35e18; // 135% ✅ Good
    uint256 public constant BORROWING_FEE_FLOOR = 0.000005e18; // 0.5% ✅ Good
    uint256 public constant MAX_BORROWING_FEE = 0.005e18; // 5% ✅ Good

    // TESTNET: Reduce minimum debt for easier testing
    uint256 public constant MIN_NET_DEBT = 10e18; // 10 USDF (was 200)

    // TESTNET: Reduce minimum adjustments
    uint256 public constant MIN_ADJUSTMENT_AMOUNT = 1e15; // 0.001 units (was 0.0001)

    // Security limits - testnet friendly
    uint256 public constant MAX_TROVES_PER_USER = 10; // ✅ Good
    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour ✅ Good
    uint256 public constant MAX_COLLATERAL_AMOUNT = 100e18; // 100 ETH (reduced from 10K)
    uint256 public constant MAX_DEBT_AMOUNT = 10000e18; // 10K USDF (reduced from 1M)

    // Gas compensation - testnet friendly
    uint256 public  gasCompensation = 0.1e18; // 0.1 USDF (reduced from 2)
    uint256 public constant MIN_GAS_COMPENSATION = 0.1e18; // 0.1 USDF
    uint256 public constant MAX_GAS_COMPENSATION = 1e18; // 1 USDF
}

// MAINNET VALUES (for reference):
contract MainnetConstants {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MIN_COLLATERAL_RATIO = 1.35e18; // 135%
    uint256 public constant BORROWING_FEE_FLOOR = 0.000005e18; // 0.5%
    uint256 public constant MAX_BORROWING_FEE = 0.005e18; // 5%
    uint256 public constant MIN_NET_DEBT = 200e18; // 200 USDF minimum

    // Security limits
    uint256 public constant MAX_TROVES_PER_USER = 10;
    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour
    uint256 public constant MAX_COLLATERAL_AMOUNT = 10000e18; // 10K ETH max
    uint256 public constant MAX_DEBT_AMOUNT = 1000000e18; // 1M USDF max
    uint256 public constant MIN_ADJUSTMENT_AMOUNT = 1e16; // 0.01 unit minimum

    // Gas compensation
    uint256 public gasCompensation = 200e18; // 200 USDF
    uint256 public constant MIN_GAS_COMPENSATION = 100e18;
    uint256 public constant MAX_GAS_COMPENSATION = 500e18;
}
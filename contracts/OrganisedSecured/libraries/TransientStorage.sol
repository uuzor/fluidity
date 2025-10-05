// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TransientStorage
 * @notice Gas-optimized transient storage library using EIP-1153
 * @dev Provides tstore/tload operations for temporary cross-function state
 *
 * Gas Savings:
 * - TSTORE: ~100 gas vs SSTORE: ~20,000 gas (cold) / ~2,900 gas (warm)
 * - TLOAD: ~100 gas vs SLOAD: ~2,100 gas (cold) / ~100 gas (warm)
 *
 * Use Cases:
 * - Reentrancy guards: Save ~19,800 gas per transaction
 * - Temporary calculation caching: Save ~2,000+ gas per cached value
 * - Cross-function communication: Save ~20,000 gas vs storage
 *
 * IMPORTANT: Data stored with tstore is cleared after transaction completion
 * DO NOT use for persistent state - only for intra-transaction data
 */
library TransientStorage {

    /**
     * @dev Store a uint256 value in transient storage
     * @param slot The storage slot (use keccak256 for named slots)
     * @param value The value to store
     *
     * Cost: ~100 gas
     *
     * Example:
     * bytes32 slot = keccak256("reentrancy.guard");
     * TransientStorage.tstore(slot, 1);
     */
    function tstore(bytes32 slot, uint256 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /**
     * @dev Load a uint256 value from transient storage
     * @param slot The storage slot to read from
     * @return value The stored value (0 if not set)
     *
     * Cost: ~100 gas
     *
     * Example:
     * bytes32 slot = keccak256("reentrancy.guard");
     * uint256 value = TransientStorage.tload(slot);
     */
    function tload(bytes32 slot) internal view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }

    /**
     * @dev Store an address in transient storage
     * @param slot The storage slot
     * @param addr The address to store
     *
     * Cost: ~100 gas
     */
    function tstoreAddress(bytes32 slot, address addr) internal {
        assembly {
            tstore(slot, addr)
        }
    }

    /**
     * @dev Load an address from transient storage
     * @param slot The storage slot to read from
     * @return addr The stored address (address(0) if not set)
     *
     * Cost: ~100 gas
     */
    function tloadAddress(bytes32 slot) internal view returns (address addr) {
        assembly {
            addr := tload(slot)
        }
    }

    /**
     * @dev Store a boolean in transient storage
     * @param slot The storage slot
     * @param value The boolean value to store
     *
     * Cost: ~100 gas
     */
    function tstoreBool(bytes32 slot, bool value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /**
     * @dev Load a boolean from transient storage
     * @param slot The storage slot to read from
     * @return value The stored boolean (false if not set)
     *
     * Cost: ~100 gas
     */
    function tloadBool(bytes32 slot) internal view returns (bool value) {
        assembly {
            value := tload(slot)
        }
    }

    /**
     * @dev Increment a counter in transient storage
     * @param slot The storage slot
     * @return newValue The incremented value
     *
     * Cost: ~200 gas (tload + tstore)
     *
     * Useful for: iteration counters, nonce tracking within transaction
     */
    function tincrement(bytes32 slot) internal returns (uint256 newValue) {
        assembly {
            newValue := add(tload(slot), 1)
            tstore(slot, newValue)
        }
    }

    /**
     * @dev Decrement a counter in transient storage
     * @param slot The storage slot
     * @return newValue The decremented value
     *
     * Cost: ~200 gas (tload + tstore)
     * Note: Will underflow if value is 0 (by design for gas optimization)
     */
    function tdecrement(bytes32 slot) internal returns (uint256 newValue) {
        assembly {
            newValue := sub(tload(slot), 1)
            tstore(slot, newValue)
        }
    }

    /**
     * @dev Clear a transient storage slot (set to 0)
     * @param slot The storage slot to clear
     *
     * Cost: ~100 gas
     * Note: Not strictly necessary as transient storage auto-clears after tx
     * but useful for explicit cleanup in complex flows
     */
    function tclear(bytes32 slot) internal {
        assembly {
            tstore(slot, 0)
        }
    }

    /**
     * @dev Store multiple values in transient storage (batch operation)
     * @param slots Array of storage slots
     * @param values Array of values to store
     *
     * Cost: ~100 gas per slot
     *
     * Example:
     * bytes32[] memory slots = new bytes32[](2);
     * slots[0] = keccak256("slot1");
     * slots[1] = keccak256("slot2");
     * uint256[] memory values = new uint256[](2);
     * values[0] = 100;
     * values[1] = 200;
     * TransientStorage.tstoreBatch(slots, values);
     */
    function tstoreBatch(bytes32[] memory slots, uint256[] memory values) internal {
        require(slots.length == values.length, "TransientStorage: length mismatch");

        assembly {
            let len := mload(slots)
            let slotsPtr := add(slots, 0x20)
            let valuesPtr := add(values, 0x20)

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                let slot := mload(add(slotsPtr, mul(i, 0x20)))
                let value := mload(add(valuesPtr, mul(i, 0x20)))
                tstore(slot, value)
            }
        }
    }

    /**
     * @dev Load multiple values from transient storage (batch operation)
     * @param slots Array of storage slots to read
     * @return values Array of loaded values
     *
     * Cost: ~100 gas per slot
     */
    function tloadBatch(bytes32[] memory slots) internal view returns (uint256[] memory values) {
        values = new uint256[](slots.length);

        assembly {
            let len := mload(slots)
            let slotsPtr := add(slots, 0x20)
            let valuesPtr := add(values, 0x20)

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                let slot := mload(add(slotsPtr, mul(i, 0x20)))
                let value := tload(slot)
                mstore(add(valuesPtr, mul(i, 0x20)), value)
            }
        }
    }
}

/**
 * @title TransientReentrancyGuard
 * @notice Gas-optimized reentrancy guard using transient storage
 * @dev Saves ~19,800 gas compared to OpenZeppelin's ReentrancyGuard
 *
 * Gas Comparison:
 * - OpenZeppelin (storage-based): ~22,000 gas (cold SSTORE + SLOAD)
 * - This (transient-based): ~200 gas (2x TSTORE + TLOAD)
 * - Savings: ~21,800 gas per protected function call
 */
abstract contract TransientReentrancyGuard {
    using TransientStorage for bytes32;

    // Transient storage slot for reentrancy guard
    bytes32 private constant REENTRANCY_GUARD_SLOT = keccak256("TransientReentrancyGuard.locked");

    error ReentrancyGuardReentrantCall();

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly
     * Cost: ~200 gas (vs ~22,000 gas for storage-based guard)
     */
    modifier nonReentrant() {
        // Check if already entered
        if (REENTRANCY_GUARD_SLOT.tload() == 1) {
            revert ReentrancyGuardReentrantCall();
        }

        // Set the guard
        REENTRANCY_GUARD_SLOT.tstore(1);

        _;

        // Clear the guard (optional, auto-clears after tx)
        REENTRANCY_GUARD_SLOT.tclear();
    }

    /**
     * @dev Check if currently in a protected call
     * @return True if in a nonReentrant function
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return REENTRANCY_GUARD_SLOT.tload() == 1;
    }
}

/**
 * @title TransientCache
 * @notice Helper contract for caching values in transient storage
 * @dev Useful for expensive calculations that are used multiple times in a transaction
 *
 * Example Use Case:
 * - Cache price oracle results (save ~20,000 gas per duplicate call)
 * - Cache ICR calculations (save ~10,000 gas per duplicate calculation)
 * - Cache user balances during complex operations
 */
abstract contract TransientCache {
    using TransientStorage for bytes32;

    /**
     * @dev Get cached value or compute and cache it
     * @param cacheSlot The transient storage slot for this cache
     * @param computeFn Function to compute value if not cached
     * @return value The cached or computed value
     *
     * Gas Savings:
     * - First call: Normal computation cost + 100 gas (tstore)
     * - Subsequent calls: 100 gas (tload) vs full computation cost
     */
    function _getCached(
        bytes32 cacheSlot,
        function() internal view returns (uint256) computeFn
    ) internal view returns (uint256 value) {
        value = cacheSlot.tload();

        if (value == 0) {
            value = computeFn();
            // Note: Can't tstore in view function, caller must cache explicitly
        }
    }

    /**
     * @dev Set cache value
     * @param cacheSlot The transient storage slot
     * @param value The value to cache
     */
    function _setCache(bytes32 cacheSlot, uint256 value) internal {
        cacheSlot.tstore(value);
    }

    /**
     * @dev Clear cache
     * @param cacheSlot The transient storage slot to clear
     */
    function _clearCache(bytes32 cacheSlot) internal {
        cacheSlot.tclear();
    }
}

/**
 * USAGE EXAMPLES:
 *
 * 1. Reentrancy Guard:
 *
 * contract MyContract is TransientReentrancyGuard {
 *     function sensitiveOperation() external nonReentrant {
 *         // Protected from reentrancy
 *         // Saves ~21,800 gas vs OpenZeppelin
 *     }
 * }
 *
 * 2. Temporary State:
 *
 * contract MyContract {
 *     using TransientStorage for bytes32;
 *
 *     bytes32 constant TEMP_SLOT = keccak256("my.temp.value");
 *
 *     function complexOperation() external {
 *         // Store intermediate result
 *         TEMP_SLOT.tstore(calculatedValue);
 *
 *         // Use in another function
 *         _helperFunction();
 *
 *         // Auto-cleared after transaction
 *     }
 *
 *     function _helperFunction() internal {
 *         uint256 temp = TEMP_SLOT.tload();
 *         // Use temp value
 *     }
 * }
 *
 * 3. Price Caching:
 *
 * contract MyProtocol is TransientCache {
 *     bytes32 constant PRICE_CACHE = keccak256("price.cache.eth");
 *
 *     function operation1() external {
 *         uint256 price = _getETHPrice();
 *         _setCache(PRICE_CACHE, price);
 *         // ... use price
 *     }
 *
 *     function operation2() external {
 *         // Reuse cached price (saves ~20,000 gas oracle call)
 *         uint256 price = PRICE_CACHE.tload();
 *         // ... use price
 *     }
 * }
 */

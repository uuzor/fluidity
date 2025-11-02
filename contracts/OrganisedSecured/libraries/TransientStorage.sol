// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// /**
//  * @title TransientStorage
//  * @notice Transient storage pattern using regular storage (Paris EVM compatible)
//  * @dev Provides tstore/tload operations for temporary cross-function state
//  *
//  * IMPORTANT CHANGES FROM ORIGINAL:
//  * - Uses sstore/sload instead of tstore/tload (Paris EVM compatible)
//  * - Data is NOT automatically cleared after transaction
//  * - MUST manually clear storage slots after use to avoid state pollution
//  * - Gas costs are higher than native transient storage:
//  *   - First write (cold): ~20,000 gas
//  *   - Subsequent writes (warm): ~2,900 gas
//  *   - Reads (warm): ~100 gas
//  *
//  * Use Cases:
//  * - Reentrancy guards with manual cleanup
//  * - Temporary calculation caching within protected contexts
//  * - Cross-function communication with explicit cleanup
//  *
//  * WARNING: Always clear storage after use to prevent state pollution!
//  */
// library TransientStorage {

//     /**
//      * @dev Store a uint256 value in pseudo-transient storage
//      * @param slot The storage slot (use keccak256 for named slots)
//      * @param value The value to store
//      *
//      * Cost: ~20,000 gas (cold) / ~2,900 gas (warm)
//      */
//     function tstore(bytes32 slot, uint256 value) internal {
//         assembly {
//             sstore(slot, value)
//         }
//     }

//     /**
//      * @dev Load a uint256 value from pseudo-transient storage
//      * @param slot The storage slot to read from
//      * @return value The stored value (0 if not set)
//      *
//      * Cost: ~2,100 gas (cold) / ~100 gas (warm)
//      */
//     function tload(bytes32 slot) internal view returns (uint256 value) {
//         assembly {
//             value := sload(slot)
//         }
//     }

//     /**
//      * @dev Store an address in pseudo-transient storage
//      * @param slot The storage slot
//      * @param addr The address to store
//      *
//      * Cost: ~20,000 gas (cold) / ~2,900 gas (warm)
//      */
//     function tstoreAddress(bytes32 slot, address addr) internal {
//         assembly {
//             sstore(slot, addr)
//         }
//     }

//     /**
//      * @dev Load an address from pseudo-transient storage
//      * @param slot The storage slot to read from
//      * @return addr The stored address (address(0) if not set)
//      *
//      * Cost: ~2,100 gas (cold) / ~100 gas (warm)
//      */
//     function tloadAddress(bytes32 slot) internal view returns (address addr) {
//         assembly {
//             addr := sload(slot)
//         }
//     }

//     /**
//      * @dev Store a boolean in pseudo-transient storage
//      * @param slot The storage slot
//      * @param value The boolean value to store
//      *
//      * Cost: ~20,000 gas (cold) / ~2,900 gas (warm)
//      */
//     function tstoreBool(bytes32 slot, bool value) internal {
//         assembly {
//             sstore(slot, value)
//         }
//     }

//     /**
//      * @dev Load a boolean from pseudo-transient storage
//      * @param slot The storage slot to read from
//      * @return value The stored boolean (false if not set)
//      *
//      * Cost: ~2,100 gas (cold) / ~100 gas (warm)
//      */
//     function tloadBool(bytes32 slot) internal view returns (bool value) {
//         assembly {
//             value := sload(slot)
//         }
//     }

//     /**
//      * @dev Increment a counter in pseudo-transient storage
//      * @param slot The storage slot
//      * @return newValue The incremented value
//      *
//      * Cost: ~2,200 gas (sload + sstore)
//      */
//     function tincrement(bytes32 slot) internal returns (uint256 newValue) {
//         assembly {
//             newValue := add(sload(slot), 1)
//             sstore(slot, newValue)
//         }
//     }

//     /**
//      * @dev Decrement a counter in pseudo-transient storage
//      * @param slot The storage slot
//      * @return newValue The decremented value
//      *
//      * Cost: ~2,200 gas (sload + sstore)
//      */
//     function tdecrement(bytes32 slot) internal returns (uint256 newValue) {
//         assembly {
//             newValue := sub(sload(slot), 1)
//             sstore(slot, newValue)
//         }
//     }

//     /**
//      * @dev Clear a pseudo-transient storage slot (set to 0)
//      * @param slot The storage slot to clear
//      *
//      * Cost: ~2,900 gas (warm sstore to 0)
//      * IMPORTANT: Must be called to prevent state pollution!
//      */
//     function tclear(bytes32 slot) internal {
//         assembly {
//             sstore(slot, 0)
//         }
//     }

//     /**
//      * @dev Store multiple values in pseudo-transient storage (batch operation)
//      * @param slots Array of storage slots
//      * @param values Array of values to store
//      *
//      * Cost: ~20,000 gas per slot (cold) / ~2,900 gas (warm)
//      */
//     function tstoreBatch(bytes32[] memory slots, uint256[] memory values) internal {
//         require(slots.length == values.length, "TransientStorage: length mismatch");

//         assembly {
//             let len := mload(slots)
//             let slotsPtr := add(slots, 0x20)
//             let valuesPtr := add(values, 0x20)

//             for { let i := 0 } lt(i, len) { i := add(i, 1) } {
//                 let slot := mload(add(slotsPtr, mul(i, 0x20)))
//                 let value := mload(add(valuesPtr, mul(i, 0x20)))
//                 sstore(slot, value)
//             }
//         }
//     }

//     /**
//      * @dev Load multiple values from pseudo-transient storage (batch operation)
//      * @param slots Array of storage slots to read
//      * @return values Array of loaded values
//      *
//      * Cost: ~2,100 gas per slot (cold) / ~100 gas (warm)
//      */
//     function tloadBatch(bytes32[] memory slots) internal view returns (uint256[] memory values) {
//         values = new uint256[](slots.length);

//         assembly {
//             let len := mload(slots)
//             let slotsPtr := add(slots, 0x20)
//             let valuesPtr := add(values, 0x20)

//             for { let i := 0 } lt(i, len) { i := add(i, 1) } {
//                 let slot := mload(add(slotsPtr, mul(i, 0x20)))
//                 let value := sload(slot)
//                 mstore(add(valuesPtr, mul(i, 0x20)), value)
//             }
//         }
//     }

//     /**
//      * @dev Clear multiple pseudo-transient storage slots (batch operation)
//      * @param slots Array of storage slots to clear
//      *
//      * Cost: ~2,900 gas per slot
//      * IMPORTANT: Call this to cleanup after batch operations!
//      */
//     function tclearBatch(bytes32[] memory slots) internal {
//         assembly {
//             let len := mload(slots)
//             let slotsPtr := add(slots, 0x20)

//             for { let i := 0 } lt(i, len) { i := add(i, 1) } {
//                 let slot := mload(add(slotsPtr, mul(i, 0x20)))
//                 sstore(slot, 0)
//             }
//         }
//     }
// }

// /**
//  * @title TransientReentrancyGuard
//  * @notice Reentrancy guard using pseudo-transient storage (Paris EVM compatible)
//  * @dev Uses regular storage with explicit cleanup
//  *
//  * Gas Comparison:
//  * - First call: ~20,000 gas (cold sstore)
//  * - Subsequent calls: ~3,000 gas (warm sstore + sload + clear)
//  * - Higher than native transient storage but still functional
//  */
// abstract contract TransientReentrancyGuard {
//     using TransientStorage for bytes32;

//     // Change from state variable to constant hex value
//     bytes32 private constant REENTRANCY_GUARD_SLOT = 0x0123456789012345678901234567890123456789012345678901234567890123;

//     error ReentrancyGuardReentrantCall();

//     modifier nonReentrant() {
//         // Use hard-coded slot in assembly
//         assembly {
//             // Load current value
//             let locked := sload(0x0123456789012345678901234567890123456789012345678901234567890123)
            
//             // Check if locked
//             if eq(locked, 1) {
//                 // Store error selector for ReentrancyGuardReentrantCall()
//                 mstore(0x00, 0xf25965c4)
//                 revert(0x00, 0x04)
//             }
            
//             // Set lock
//             sstore(0x0123456789012345678901234567890123456789012345678901234567890123, 1)
//         }

//         _;

//         // Clear lock
//         assembly {
//             sstore(0x0123456789012345678901234567890123456789012345678901234567890123, 0)
//         }
//     }

//     function _reentrancyGuardEntered() internal view returns (bool) {
//         uint256 locked;
//         assembly {
//             locked := sload(0x0123456789012345678901234567890123456789012345678901234567890123)
//         }
//         return locked == 1;
//     }
// }
// /**
//  * @title TransientCache
//  * @notice Helper contract for caching values in pseudo-transient storage
//  * @dev Useful for expensive calculations used multiple times in a transaction
//  *
//  * IMPORTANT: Must manually clear cache after transaction to prevent stale data!
//  *
//  * Example Usage:
//  * contract MyContract is TransientCache {
//  *     bytes32 constant PRICE_CACHE = keccak256("price.cache");
//  *     
//  *     function operation() external transientContext {
//  *         uint256 price1 = _getOrComputePrice(); // Computes and caches
//  *         uint256 price2 = _getOrComputePrice(); // Returns cached value
//  *         // ... use prices
//  *         // Cache auto-cleared by transientContext modifier
//  *     }
//  * }
//  */
// abstract contract TransientCache {
//     using TransientStorage for bytes32;

//     // Track which slots were used for automatic cleanup
//     bytes32[] private _usedCacheSlots;
//     bool private _inTransientContext;

//     /**
//      * @dev Modifier that automatically clears all cached values after execution
//      * Use this to wrap functions that use caching
//      */
//     modifier transientContext() {
//         require(!_inTransientContext, "TransientCache: nested context not allowed");
//         _inTransientContext = true;

//         _;

//         // Clear all cached values
//         _clearAllCaches();
//         _inTransientContext = false;
//     }

//     /**
//      * @dev Get cached value or compute and cache it
//      * @param cacheSlot The storage slot for this cache
//      * @param value The value to cache if not already cached
//      * @return The cached value
//      *
//      * Note: Caller must check if value exists and compute before calling
//      */
//     function _cacheValue(bytes32 cacheSlot, uint256 value) internal returns (uint256) {
//         uint256 cached = cacheSlot.tload();
        
//         if (cached == 0 && value != 0) {
//             cacheSlot.tstore(value);
//             _trackCacheSlot(cacheSlot);
//             return value;
//         }
        
//         return cached != 0 ? cached : value;
//     }

//     /**
//      * @dev Set cache value explicitly
//      * @param cacheSlot The storage slot
//      * @param value The value to cache
//      */
//     function _setCache(bytes32 cacheSlot, uint256 value) internal {
//         cacheSlot.tstore(value);
//         _trackCacheSlot(cacheSlot);
//     }

//     /**
//      * @dev Get cached value
//      * @param cacheSlot The storage slot
//      * @return The cached value (0 if not set)
//      */
//     function _getCache(bytes32 cacheSlot) internal view returns (uint256) {
//         return cacheSlot.tload();
//     }

//     /**
//      * @dev Clear specific cache
//      * @param cacheSlot The storage slot to clear
//      */
//     function _clearCache(bytes32 cacheSlot) internal {
//         cacheSlot.tclear();
//     }

//     /**
//      * @dev Track a cache slot for automatic cleanup
//      * @param slot The slot to track
//      */
//     function _trackCacheSlot(bytes32 slot) private {
//         // Check if already tracked to avoid duplicates
//         for (uint256 i = 0; i < _usedCacheSlots.length; i++) {
//             if (_usedCacheSlots[i] == slot) {
//                 return;
//             }
//         }
//         _usedCacheSlots.push(slot);
//     }

//     /**
//      * @dev Clear all tracked caches
//      */
//     function _clearAllCaches() private {
//         TransientStorage.tclearBatch(_usedCacheSlots);
//         delete _usedCacheSlots;
//     }
// }

// /**
//  * @title TransientContext
//  * @notice Advanced context manager with automatic cleanup
//  * @dev Provides a safe way to use pseudo-transient storage with guaranteed cleanup
//  *
//  * Usage:
//  * contract MyContract is TransientContext {
//  *     function myFunction() external withTransientContext {
//  *         bytes32 slot = _getContextSlot("mydata");
//  *         _contextStore(slot, 12345);
//  *         uint256 value = _contextLoad(slot);
//  *         // Automatically cleaned up after function
//  *     }
//  * }
//  */
// abstract contract TransientContext {
//     using TransientStorage for bytes32;

//     bytes32[] private _contextSlots;
//     bool private _locked;

//     error TransientContextReentrant();
//     error TransientContextNotActive();

//     /**
//      * @dev Modifier that provides automatic cleanup of all context storage
//      */
//     modifier withTransientContext() {
//         if (_locked) revert TransientContextReentrant();
//         _locked = true;

//         _;

//         _cleanupContext();
//         _locked = false;
//     }

//     /**
//      * @dev Generate a context-specific storage slot
//      * @param key Identifier for this slot
//      * @return slot The generated slot
//      */
//     function _getContextSlot(string memory key) internal pure returns (bytes32) {
//         return keccak256(abi.encodePacked("TransientContext.", key));
//     }

//     /**
//      * @dev Store value in context with automatic tracking
//      * @param slot The storage slot
//      * @param value The value to store
//      */
//     function _contextStore(bytes32 slot, uint256 value) internal {
//         if (!_locked) revert TransientContextNotActive();
        
//         slot.tstore(value);
//         _trackSlot(slot);
//     }

//     /**
//      * @dev Load value from context
//      * @param slot The storage slot
//      * @return The stored value
//      */
//     function _contextLoad(bytes32 slot) internal view returns (uint256) {
//         return slot.tload();
//     }

//     /**
//      * @dev Track a slot for cleanup
//      * @param slot The slot to track
//      */
//     function _trackSlot(bytes32 slot) private {
//         for (uint256 i = 0; i < _contextSlots.length; i++) {
//             if (_contextSlots[i] == slot) return;
//         }
//         _contextSlots.push(slot);
//     }

//     /**
//      * @dev Cleanup all tracked context slots
//      */
//     function _cleanupContext() private {
//         TransientStorage.tclearBatch(_contextSlots);
//         delete _contextSlots;
//     }
// }

























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

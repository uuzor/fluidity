// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title OptimizedDataStructures
 * @dev Gas-optimized data structures for Fluid Protocol
 */
library OptimizedDataStructures {
    
    /**
     * @dev Circular buffer for price history - O(1) operations
     */
    struct CircularBuffer {
        uint256[30] data;
        uint256 head;
        uint256 size;
        bool initialized;
    }
    
    function initBuffer(CircularBuffer storage buffer) internal {
        buffer.head = 0;
        buffer.size = 0;
        buffer.initialized = true;
    }
    
    function push(CircularBuffer storage buffer, uint256 value) internal {
        require(buffer.initialized, "Buffer not initialized");
        
        buffer.data[buffer.head] = value;
        buffer.head = (buffer.head + 1) % 30;
        
        if (buffer.size < 30) {
            buffer.size++;
        }
    }
    
    function getLatest(CircularBuffer storage buffer) internal view returns (uint256) {
        require(buffer.size > 0, "Buffer is empty");
        uint256 latestIndex = buffer.head == 0 ? 29 : buffer.head - 1;
        return buffer.data[latestIndex];
    }
    
    function getAverage(CircularBuffer storage buffer) internal view returns (uint256) {
        require(buffer.size > 0, "Buffer is empty");
        
        uint256 sum = 0;
        for (uint256 i = 0; i < buffer.size; i++) {
            sum += buffer.data[i];
        }
        return sum / buffer.size;
    }
    
    function getVariance(CircularBuffer storage buffer) internal view returns (uint256) {
        require(buffer.size > 1, "Need at least 2 data points");
        
        uint256 mean = getAverage(buffer);
        uint256 sumSquaredDiff = 0;
        
        for (uint256 i = 0; i < buffer.size; i++) {
            uint256 diff = buffer.data[i] > mean ? 
                buffer.data[i] - mean : 
                mean - buffer.data[i];
            sumSquaredDiff += (diff * diff) / 1e18; // Normalize for precision
        }
        
        return sumSquaredDiff / (buffer.size - 1);
    }
    
    /**
     * @dev Packed struct for gas optimization
     */
    struct PackedTrove {
        uint128 debt;           // Sufficient for most debt amounts
        uint128 collateral;     // Sufficient for most collateral amounts
        uint64 lastUpdate;      // Unix timestamp fits in uint64
        uint32 status;          // Enum values fit in uint32
        // Total: 352 bits = 2 storage slots (vs 4 slots for separate uint256s)
    }
    
    function packTrove(
        uint256 debt,
        uint256 collateral,
        uint256 lastUpdate,
        uint256 status
    ) internal pure returns (PackedTrove memory) {
        require(debt <= type(uint128).max, "Debt too large");
        require(collateral <= type(uint128).max, "Collateral too large");
        require(lastUpdate <= type(uint64).max, "Timestamp too large");
        require(status <= type(uint32).max, "Status too large");
        
        return PackedTrove({
            debt: uint128(debt),
            collateral: uint128(collateral),
            lastUpdate: uint64(lastUpdate),
            status: uint32(status)
        });
    }
    
    function unpackTrove(PackedTrove memory packed) internal pure returns (
        uint256 debt,
        uint256 collateral,
        uint256 lastUpdate,
        uint256 status
    ) {
        debt = uint256(packed.debt);
        collateral = uint256(packed.collateral);
        lastUpdate = uint256(packed.lastUpdate);
        status = uint256(packed.status);
    }
    
    /**
     * @dev Bitmap for efficient boolean storage
     */
    struct Bitmap {
        mapping(uint256 => uint256) data;
    }
    
    function set(Bitmap storage bitmap, uint256 index) internal {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        bitmap.data[wordIndex] |= (1 << bitIndex);
    }
    
    function unset(Bitmap storage bitmap, uint256 index) internal {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        bitmap.data[wordIndex] &= ~(1 << bitIndex);
    }
    
    function isSet(Bitmap storage bitmap, uint256 index) internal view returns (bool) {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        return (bitmap.data[wordIndex] & (1 << bitIndex)) != 0;
    }
    
    /**
     * @dev Efficient square root calculation
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        // Initial guess
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        
        // Newton's method
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }
    
    /**
     * @dev Batch operations helper
     */
    struct BatchOperation {
        address target;
        bytes data;
        uint256 value;
    }
    
    function executeBatch(
        BatchOperation[] memory operations
    ) internal returns (bytes[] memory results) {
        results = new bytes[](operations.length);
        
        for (uint256 i = 0; i < operations.length; i++) {
            BatchOperation memory op = operations[i];
            
            (bool success, bytes memory result) = op.target.call{value: op.value}(op.data);
            require(success, "Batch operation failed");
            
            results[i] = result;
        }
    }
    
    /**
     * @dev Memory-efficient array operations
     */
    function quickSort(uint256[] memory arr, uint256 left, uint256 right) internal pure {
        if (left < right) {
            uint256 pivotIndex = partition(arr, left, right);
            if (pivotIndex > 0) {
                quickSort(arr, left, pivotIndex - 1);
            }
            quickSort(arr, pivotIndex + 1, right);
        }
    }
    
    function partition(uint256[] memory arr, uint256 left, uint256 right) internal pure returns (uint256) {
        uint256 pivot = arr[right];
        uint256 i = left;
        
        for (uint256 j = left; j < right; j++) {
            if (arr[j] <= pivot) {
                (arr[i], arr[j]) = (arr[j], arr[i]);
                i++;
            }
        }
        
        (arr[i], arr[right]) = (arr[right], arr[i]);
        return i;
    }
}

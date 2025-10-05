// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CalldataDecoder
 * @notice Gas-optimized parameter encoding/decoding for function calls
 * @dev Reduces calldata costs by packing multiple parameters into single bytes32
 *
 * Gas Savings:
 * - Calldata cost: 16 gas per non-zero byte, 4 gas per zero byte
 * - openTrove unpacked: ~156 bytes = ~2,496 gas
 * - openTrove packed: ~32 bytes = ~512 gas
 * - Savings: ~1,984 gas per call
 *
 * Trade-offs:
 * - Slightly more complex to use (encode off-chain, decode on-chain)
 * - Value limits (uint80 max = 1.2M ETH, sufficient for most cases)
 * - Saves gas for users, worth the complexity
 */
library CalldataDecoder {

    /**
     * @dev Error thrown when encoded value exceeds maximum for its bit size
     */
    error ValueOverflow(string param, uint256 value, uint256 max);

    /**
     * ENCODING LAYOUT FOR openTrove:
     *
     * bytes32 packed:
     * [0-15]    maxFeePercentage (uint16)  - Max: 65,535 (65.535% = way more than needed)
     * [16-95]   collAmount (uint80)        - Max: 1.2M ETH (1,208,925 ETH)
     * [96-175]  usdfAmount (uint80)        - Max: 1.2M USDF
     * [176-255] hints (uint80)             - Encoded hint data
     *
     * Total: 256 bits = 32 bytes of calldata
     * vs 156 bytes unpacked (address + 4 uint256s)
     * Savings: 124 bytes � 16 gas = 1,984 gas
     */

    // Bit positions
    uint256 private constant MAX_FEE_OFFSET = 0;
    uint256 private constant MAX_FEE_MASK = (1 << 16) - 1; // 16 bits

    uint256 private constant COLL_AMOUNT_OFFSET = 16;
    uint256 private constant COLL_AMOUNT_MASK = ((1 << 80) - 1) << 16; // 80 bits at position 16

    uint256 private constant USDF_AMOUNT_OFFSET = 96;
    uint256 private constant USDF_AMOUNT_MASK = ((1 << 80) - 1) << 96; // 80 bits at position 96

    uint256 private constant HINTS_OFFSET = 176;
    uint256 private constant HINTS_MASK = ((1 << 80) - 1) << 176; // 80 bits at position 176

    // Maximum values
    uint256 private constant MAX_FEE_MAX = (1 << 16) - 1; // 65,535
    uint256 private constant AMOUNT_MAX = (1 << 80) - 1; // 1.2M ETH with 18 decimals

    /**
     * @dev Encode openTrove parameters into single bytes32
     * @param maxFeePercentage Maximum fee percentage (basis points, e.g. 500 = 5%)
     * @param collAmount Collateral amount in wei
     * @param usdfAmount USDF to borrow in wei
     * @param hintsEncoded Encoded hint data (upper/lower hints packed)
     * @return packed The packed bytes32 parameter
     *
     * Cost: ~500 gas (pure function, off-chain preferred)
     *
     * Example:
     * bytes32 packed = CalldataDecoder.encodeOpenTrove(
     *     500,                    // 5% max fee
     *     10 ether,              // 10 ETH collateral
     *     5000 ether,            // 5000 USDF
     *     0                      // no hints
     * );
     */
    function encodeOpenTrove(
        uint16 maxFeePercentage,
        uint256 collAmount,
        uint256 usdfAmount,
        uint80 hintsEncoded
    ) internal pure returns (bytes32 packed) {
        // Validate bounds
        if (collAmount > AMOUNT_MAX) {
            revert ValueOverflow("collAmount", collAmount, AMOUNT_MAX);
        }
        if (usdfAmount > AMOUNT_MAX) {
            revert ValueOverflow("usdfAmount", usdfAmount, AMOUNT_MAX);
        }

        assembly {
            // Pack all fields into single 256-bit value
            packed := or(
                maxFeePercentage,
                or(
                    shl(COLL_AMOUNT_OFFSET, collAmount),
                    or(
                        shl(USDF_AMOUNT_OFFSET, usdfAmount),
                        shl(HINTS_OFFSET, hintsEncoded)
                    )
                )
            )
        }
    }

    /**
     * @dev Decode openTrove parameters from bytes32
     * @param packed The packed bytes32 parameter
     * @return maxFeePercentage Maximum fee percentage
     * @return collAmount Collateral amount in wei
     * @return usdfAmount USDF to borrow in wei
     * @return hintsEncoded Encoded hint data
     *
     * Cost: ~300 gas (bit manipulation)
     *
     * Example:
     * (uint16 maxFee, uint256 coll, uint256 usdf, uint80 hints) =
     *     CalldataDecoder.decodeOpenTrove(packed);
     */
    function decodeOpenTrove(bytes32 packed)
        internal
        pure
        returns (
            uint16 maxFeePercentage,
            uint256 collAmount,
            uint256 usdfAmount,
            uint80 hintsEncoded
        )
    {
        assembly {
            // Extract each field using bit masks and shifts
            maxFeePercentage := and(packed, MAX_FEE_MASK)
            collAmount := and(shr(COLL_AMOUNT_OFFSET, packed), sub(shl(80, 1), 1))
            usdfAmount := and(shr(USDF_AMOUNT_OFFSET, packed), sub(shl(80, 1), 1))
            hintsEncoded := and(shr(HINTS_OFFSET, packed), sub(shl(80, 1), 1))
        }
    }

    /**
     * ENCODING LAYOUT FOR adjustTrove:
     *
     * bytes32 packed:
     * [0-15]    maxFeePercentage (uint16)
     * [16-95]   collChange (uint80)
     * [96-175]  usdfChange (uint80)
     * [176]     isCollIncrease (bool) - 1 bit
     * [177]     isDebtIncrease (bool) - 1 bit
     * [178-255] hints (uint78) - Remaining bits
     */

    uint256 private constant IS_COLL_INCREASE_OFFSET = 176;
    uint256 private constant IS_DEBT_INCREASE_OFFSET = 177;
    uint256 private constant ADJUST_HINTS_OFFSET = 178;

    /**
     * @dev Encode adjustTrove parameters
     * @param maxFeePercentage Maximum fee percentage
     * @param collChange Collateral change amount
     * @param usdfChange USDF change amount
     * @param isCollIncrease True if adding collateral
     * @param isDebtIncrease True if increasing debt
     * @param hintsEncoded Encoded hints
     * @return packed The packed bytes32 parameter
     */
    function encodeAdjustTrove(
        uint16 maxFeePercentage,
        uint256 collChange,
        uint256 usdfChange,
        bool isCollIncrease,
        bool isDebtIncrease,
        uint64 hintsEncoded
    ) internal pure returns (bytes32 packed) {
        if (collChange > AMOUNT_MAX) {
            revert ValueOverflow("collChange", collChange, AMOUNT_MAX);
        }
        if (usdfChange > AMOUNT_MAX) {
            revert ValueOverflow("usdfChange", usdfChange, AMOUNT_MAX);
        }

        assembly {
            packed := or(
                maxFeePercentage,
                or(
                    shl(COLL_AMOUNT_OFFSET, collChange),
                    or(
                        shl(USDF_AMOUNT_OFFSET, usdfChange),
                        or(
                            shl(IS_COLL_INCREASE_OFFSET, isCollIncrease),
                            or(
                                shl(IS_DEBT_INCREASE_OFFSET, isDebtIncrease),
                                shl(ADJUST_HINTS_OFFSET, hintsEncoded)
                            )
                        )
                    )
                )
            )
        }
    }

    /**
     * @dev Decode adjustTrove parameters
     */
    function decodeAdjustTrove(bytes32 packed)
        internal
        pure
        returns (
            uint16 maxFeePercentage,
            uint256 collChange,
            uint256 usdfChange,
            bool isCollIncrease,
            bool isDebtIncrease,
            uint64 hintsEncoded
        )
    {
        assembly {
            maxFeePercentage := and(packed, MAX_FEE_MASK)
            collChange := and(shr(COLL_AMOUNT_OFFSET, packed), sub(shl(80, 1), 1))
            usdfChange := and(shr(USDF_AMOUNT_OFFSET, packed), sub(shl(80, 1), 1))
            isCollIncrease := and(shr(IS_COLL_INCREASE_OFFSET, packed), 1)
            isDebtIncrease := and(shr(IS_DEBT_INCREASE_OFFSET, packed), 1)
            hintsEncoded := and(shr(ADJUST_HINTS_OFFSET, packed), sub(shl(78, 1), 1))
        }
    }

    /**
     * @dev Pack two addresses (hints) into uint160
     * @param upper Upper hint address
     * @param lower Lower hint address
     * @return packed Packed hints (80 bits each)
     *
     * Note: Addresses are 160 bits, but we only use first 80 bits of each
     * This is sufficient for hint purposes (collision resistance)
     */
    function packHints(address upper, address lower) internal pure returns (uint160 packed) {
        assembly {
            // Take first 80 bits of each address
            let upperBits := and(upper, sub(shl(80, 1), 1))
            let lowerBits := and(lower, sub(shl(80, 1), 1))

            // Pack: upper in low 80 bits, lower in high 80 bits
            packed := or(upperBits, shl(80, lowerBits))
        }
    }

    /**
     * @dev Unpack hints from uint160
     * @param packed Packed hints
     * @return upper Upper hint address (reconstructed)
     * @return lower Lower hint address (reconstructed)
     *
     * Note: Reconstructed addresses only have 80 bits of entropy
     * This is fine for hints (used for gas optimization, not security)
     */
    function unpackHints(uint160 packed) internal pure returns (address upper, address lower) {
        assembly {
            upper := and(packed, sub(shl(80, 1), 1))
            lower := and(shr(80, packed), sub(shl(80, 1), 1))
        }
    }

    /**
     * @dev Helper: Convert percentage to basis points for encoding
     * @param percentage Percentage (e.g., 5.5 for 5.5%)
     * @return basisPoints Basis points (e.g., 550 for 5.5%)
     *
     * Example: percentageToBasisPoints(5.5e18) = 550
     */
    function percentageToBasisPoints(uint256 percentage) internal pure returns (uint16 basisPoints) {
        uint256 bps = percentage / 1e16; // Divide by 1e16 to convert from 1e18 to basis points
        if (bps > MAX_FEE_MAX) {
            revert ValueOverflow("basisPoints", bps, MAX_FEE_MAX);
        }
        basisPoints = uint16(bps);
    }

    /**
     * @dev Helper: Convert basis points to percentage for decoding
     * @param basisPoints Basis points (e.g., 550)
     * @return percentage Percentage in 1e18 precision (e.g., 5.5e18)
     */
    function basisPointsToPercentage(uint16 basisPoints) internal pure returns (uint256 percentage) {
        percentage = uint256(basisPoints) * 1e16; // Multiply by 1e16 to convert to 1e18 precision
    }
}

/**
 * USAGE EXAMPLES:
 *
 * 1. Off-chain Encoding (JavaScript/TypeScript):
 *
 * // User wants to openTrove with:
 * // - 5% max fee
 * // - 10 ETH collateral
 * // - 5000 USDF borrow
 *
 * const maxFee = 500; // 5% in basis points
 * const coll = ethers.parseEther("10");
 * const usdf = ethers.parseEther("5000");
 * const hints = 0; // No hints
 *
 * // Pack into bytes32 off-chain (saves gas!)
 * const packed = ethers.solidityPacked(
 *     ["uint16", "uint80", "uint80", "uint80"],
 *     [maxFee, coll, usdf, hints]
 * );
 *
 * // Call contract with single bytes32
 * await borrowerOps.openTrove(asset, packed);
 * // Saves ~1,984 gas vs separate parameters!
 *
 * 2. On-chain Decoding:
 *
 * contract BorrowerOperations {
 *     function openTrove(address asset, bytes32 packed) external {
 *         // Decode parameters (~300 gas)
 *         (
 *             uint16 maxFee,
 *             uint256 coll,
 *             uint256 usdf,
 *             uint80 hints
 *         ) = CalldataDecoder.decodeOpenTrove(packed);
 *
 *         // Use decoded values
 *         _openTrove(asset, maxFee, coll, usdf);
 *
 *         // Net savings: 1,984 - 300 = 1,684 gas!
 *     }
 * }
 *
 * 3. With Hints:
 *
 * // Off-chain: Pack hints
 * const upperHint = "0x1234...";
 * const lowerHint = "0x5678...";
 *
 * const hintsEncoded = CalldataDecoder.packHints(upperHint, lowerHint);
 *
 * const packed = CalldataDecoder.encodeOpenTrove(
 *     500, coll, usdf, hintsEncoded
 * );
 *
 * // On-chain: Unpack hints
 * (uint16 maxFee, uint256 coll, uint256 usdf, uint160 hintsEncoded) =
 *     CalldataDecoder.decodeOpenTrove(packed);
 *
 * (address upper, address lower) = CalldataDecoder.unpackHints(hintsEncoded);
 */

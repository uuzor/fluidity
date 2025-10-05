// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Math
 * @dev Mathematical functions for the Fluid Protocol
 */
library Math {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_WAD = WAD / 2;
    uint256 internal constant HALF_RAY = RAY / 2;

    /**
     * @dev Multiplies two wad numbers and returns a wad number
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return (a * b + HALF_WAD) / WAD;
    }

    /**
     * @dev Divides two wad numbers and returns a wad number
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Division by zero");
        return (a * WAD + b / 2) / b;
    }

    /**
     * @dev Multiplies two ray numbers and returns a ray number
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return (a * b + HALF_RAY) / RAY;
    }

    /**
     * @dev Divides two ray numbers and returns a ray number
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Division by zero");
        return (a * RAY + b / 2) / b;
    }

    /**
     * @dev Converts wad to ray
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * (RAY / WAD);
    }

    /**
     * @dev Converts ray to wad
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        return (a + (RAY / WAD) / 2) / (RAY / WAD);
    }

    /**
     * @dev Calculates the square root of a number using the Babylonian method
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }

    /**
     * @dev Calculates a^b using binary exponentiation
     */
    function pow(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) return WAD;
        if (a == 0) return 0;
        
        uint256 result = WAD;
        uint256 base = a;
        
        while (b > 0) {
            if (b & 1 == 1) {
                result = wadMul(result, base);
            }
            base = wadMul(base, base);
            b >>= 1;
        }
        
        return result;
    }

    /**
     * @dev Calculates the natural logarithm of a wad number
     */
    function ln(uint256 x) internal pure returns (int256) {
        require(x > 0, "Cannot take ln of zero or negative number");
        
        if (x == WAD) return 0;
        
        bool negative = x < WAD;
        if (negative) {
            x = wadDiv(WAD, x);
        }
        
        // Use Taylor series approximation
        uint256 y = x - WAD;
        uint256 term = y;
        int256 result = int256(term);
        
        for (uint256 i = 2; i <= 10; i++) {
            term = wadMul(term, y);
            int256 termSigned = int256(term / i);
            if (i % 2 == 0) {
                result -= termSigned;
            } else {
                result += termSigned;
            }
        }
        
        return negative ? -result : result;
    }

    /**
     * @dev Calculates e^x for a wad number
     */
    function exp(int256 x) internal pure returns (uint256) {
        if (x < 0) {
            return wadDiv(WAD, exp(-x));
        }
        
        uint256 ux = uint256(x);
        uint256 result = WAD;
        uint256 term = WAD;
        
        for (uint256 i = 1; i <= 20; i++) {
            term = wadMul(term, ux) / i;
            result += term;
            if (term < 1000) break; // Precision threshold
        }
        
        return result;
    }

    /**
     * @dev Multiplies and divides with full precision
     */
    function mulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        require(c != 0, "Division by zero");
        
        // Handle overflow
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        
        // Handle non-overflow cases
        if (prod1 == 0) {
            return prod0 / c;
        }
        
        // Make sure the result is less than 2^256
        require(prod1 < c, "Math: mulDiv overflow");
        
        // 512 by 256 division
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, c)
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }
        
        // Factor powers of two out of denominator and compute largest power of two divisor of denominator
        uint256 twos = c & (~c + 1);
        assembly {
            c := div(c, twos)
            prod0 := div(prod0, twos)
            twos := add(div(sub(0, twos), twos), 1)
        }
        
        prod0 |= prod1 * twos;
        
        // Invert denominator mod 2^256
        uint256 inverse = (3 * c) ^ 2;
        inverse *= 2 - c * inverse; // inverse mod 2^8
        inverse *= 2 - c * inverse; // inverse mod 2^16
        inverse *= 2 - c * inverse; // inverse mod 2^32
        inverse *= 2 - c * inverse; // inverse mod 2^64
        inverse *= 2 - c * inverse; // inverse mod 2^128
        inverse *= 2 - c * inverse; // inverse mod 2^256
        
        return prod0 * inverse;
    }

    /**
     * @dev Returns the minimum of two numbers
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the maximum of two numbers
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the absolute value of a signed integer
     */
    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /**
     * @dev Calculates compound interest
     */
    function compoundInterest(uint256 principal, uint256 rate, uint256 time) internal pure returns (uint256) {
        if (rate == 0 || time == 0) return principal;
        
        // Use approximation: (1 + r)^t ≈ e^(r*t)
        int256 exponent = int256(wadMul(rate, time));
        uint256 multiplier = exp(exponent);
        
        return wadMul(principal, multiplier);
    }

    /**
     * @dev Calculates the weighted average of two values
     */
    function weightedAverage(uint256 value1, uint256 weight1, uint256 value2, uint256 weight2) internal pure returns (uint256) {
        uint256 totalWeight = weight1 + weight2;
        require(totalWeight > 0, "Total weight must be positive");
        
        return (value1 * weight1 + value2 * weight2) / totalWeight;
    }
}
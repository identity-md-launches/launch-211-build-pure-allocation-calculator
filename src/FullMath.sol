// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Exact floor(x * y / denominator) with a 512-bit intermediate product.
/// @dev Uses the standard CRT / modular-inverse technique described by Remco Bloemen:
/// https://xn--2-umb.com/21/muldiv/ (MIT). No linked library or runtime dependency.
library FullMath {
    error ZeroDenominator();
    error QuotientOverflow();

    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        if (denominator == 0) revert ZeroDenominator();

        // All wrapping below is intentional arithmetic modulo 2^256.
        unchecked {
            uint256 low;
            uint256 high;
            assembly ("memory-safe") {
                let mm := mulmod(x, y, not(0))
                low := mul(x, y)
                high := sub(sub(mm, low), lt(mm, low))
            }

            if (high == 0) return low / denominator;
            // The quotient fits in one word exactly when denominator > high.
            if (denominator <= high) revert QuotientOverflow();

            // Subtract the remainder from the 512-bit product, making division exact.
            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)
                high := sub(high, gt(remainder, low))
                low := sub(low, remainder)
            }

            // Remove powers of two from the denominator and shift the full product.
            uint256 twos = denominator & (0 - denominator);
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                low := div(low, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            low |= high * twos;

            // The denominator is now odd. Newton iteration doubles inverse precision
            // from 4 to 8, 16, 32, 64, 128, then 256 bits.
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            result = low * inverse;
        }
    }
}

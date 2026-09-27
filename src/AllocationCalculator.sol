// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FullMath} from "./FullMath.sol";

/// @notice Stateless largest-remainder allocation; never transfers ETH or tokens.
contract AllocationCalculator {
    error InvalidRecipientCount(uint256 count);
    error LengthMismatch(uint256 recipients, uint256 weights);
    error ZeroRecipient(uint256 index);
    error DuplicateRecipient(uint256 firstIndex, uint256 duplicateIndex);
    error ZeroWeight(uint256 index);
    error TotalWeightOverflow();

    /// @notice Returns allocations in the same order as recipients.
    /// @dev Requires 1..16 distinct, nonzero recipients, positive weights, and a weight
    /// sum <= uint256.max. Amount may be any uint256, including zero and uint256.max.
    /// Each result is floor(amount * weight / totalWeight), plus one for the largest
    /// remainders until the amount is exhausted. Equal remainders favor smaller indices.
    /// Products use exact 512-bit mulDiv; remainders use EVM mulmod without truncation.
    function allocate(uint256 amount, address[] calldata recipients, uint256[] calldata weights)
        external
        pure
        returns (uint256[] memory allocations)
    {
        uint256 count = recipients.length;
        if (count == 0 || count > 16) revert InvalidRecipientCount(count);
        if (weights.length != count) revert LengthMismatch(count, weights.length);

        uint256 totalWeight = 0;
        for (uint256 i; i < count; ++i) {
            if (recipients[i] == address(0)) revert ZeroRecipient(i);
            for (uint256 j; j < i; ++j) {
                if (recipients[j] == recipients[i]) revert DuplicateRecipient(j, i);
            }
            uint256 weight = weights[i];
            if (weight == 0) revert ZeroWeight(i);
            if (weight > type(uint256).max - totalWeight) revert TotalWeightOverflow();
            totalWeight += weight;
        }

        allocations = new uint256[](count);
        uint256[] memory remainders = new uint256[](count);
        uint256 allocated = 0;
        for (uint256 i; i < count; ++i) {
            allocations[i] = FullMath.mulDiv(amount, weights[i], totalWeight);
            remainders[i] = mulmod(amount, weights[i], totalWeight);
            // Every partial sum is <= amount, so checked addition cannot overflow.
            allocated += allocations[i];
        }

        uint256 remaining = amount - allocated;
        if (remaining == 0) return allocations;

        // Count predecessors in the total order (remainder descending, index ascending).
        // Exactly `remaining` distinct entries have rank < remaining. With <=16 entries,
        // O(n^2) work is bounded and requires neither sorting nor repeated awards.
        for (uint256 i; i < count; ++i) {
            uint256 rank = 0;
            for (uint256 j; j < count; ++j) {
                if (remainders[j] > remainders[i] || (remainders[j] == remainders[i] && j < i)) {
                    ++rank;
                }
            }
            if (rank < remaining) ++allocations[i];
        }
    }
}

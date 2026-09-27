// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AllocationCalculator} from "../src/AllocationCalculator.sol";
import {TestBase} from "./TestBase.sol";

contract AllocationCalculatorTest is TestBase {
    AllocationCalculator internal calculator;

    function setUp() public {
        calculator = new AllocationCalculator();
    }

    function testZeroAmountStillValidatesInputs() public view {
        assertEq(calculator.allocate(0, _recipients(3), _three(1, 2, 3)), _three(0, 0, 0));
        _expect(
            0,
            _recipients(3),
            _three(1, 0, 3),
            abi.encodeWithSelector(AllocationCalculator.ZeroWeight.selector, 1)
        );
        address[] memory recipients = _recipients(3);
        recipients[2] = recipients[0];
        _expect(
            0,
            recipients,
            _three(1, 2, 3),
            abi.encodeWithSelector(AllocationCalculator.DuplicateRecipient.selector, 0, 2)
        );
    }

    function testOneRecipientAcceptsMaximumAmountAndWeight() public view {
        uint256[] memory weights = new uint256[](1);
        weights[0] = type(uint256).max;
        assertEq(calculator.allocate(type(uint256).max, _recipients(1), weights), weights);
    }

    function testTinyAmountsAndTies() public view {
        uint256[] memory weights = _three(1, 1, 1);
        assertEq(calculator.allocate(1, _recipients(3), weights), _three(1, 0, 0));
        assertEq(calculator.allocate(2, _recipients(3), weights), _three(1, 1, 0));
        assertEq(calculator.allocate(4, _recipients(3), weights), _three(2, 1, 1));
        assertEq(calculator.allocate(5, _recipients(3), weights), _three(2, 2, 1));
    }

    function testUnequalWeightsDemo() public view {
        assertEq(calculator.allocate(10, _recipients(3), _three(1, 2, 3)), _three(2, 3, 5));
        assertEq(calculator.allocate(2, _recipients(3), _three(1, 2, 3)), _three(0, 1, 1));
        assertEq(calculator.allocate(1, _recipients(3), _three(1, 9, 2)), _three(0, 1, 0));
    }

    function testExactDivisibilityAwardsNoBonus() public view {
        assertEq(calculator.allocate(60, _recipients(3), _three(1, 2, 3)), _three(10, 20, 30));
    }

    function testTieBetweenDifferentWeights() public view {
        // 2 * [1, 3, 4] / 8 has floors [0, 0, 1] and remainders [2, 6, 0].
        assertEq(calculator.allocate(2, _recipients(3), _three(1, 3, 4)), _three(0, 1, 1));
        // 2 * [1, 3, 4] / 8 above is untied; amount 4 ties the first two at 4/8.
        assertEq(calculator.allocate(4, _recipients(3), _three(1, 3, 4)), _three(1, 1, 2));
    }

    function testAllPermutationsOfUnequalWeightsWithoutTies() public view {
        address[] memory original = _recipients(3);
        uint256[] memory weights = _three(1, 2, 3);
        uint256[] memory expected = _three(2, 3, 5);
        for (uint256 i; i < 3; ++i) {
            for (uint256 j; j < 3; ++j) {
                if (i == j) continue;
                uint256 k = 3 - i - j;
                address[] memory permuted = new address[](3);
                permuted[0] = original[i];
                permuted[1] = original[j];
                permuted[2] = original[k];
                assertEq(
                    calculator.allocate(10, permuted, _three(weights[i], weights[j], weights[k])),
                    _three(expected[i], expected[j], expected[k])
                );
            }
        }
    }

    function testPermutationWithTiesUsesNewIndexNotAddressOrder() public view {
        address[] memory recipients = _recipients(3);
        (recipients[0], recipients[2]) = (recipients[2], recipients[0]);
        assertEq(calculator.allocate(1, recipients, _three(1, 1, 1)), _three(1, 0, 0));
        // With unequal weights, swapping tied entries moves the bonus with the index.
        assertEq(calculator.allocate(4, recipients, _three(3, 1, 4)), _three(2, 0, 2));
    }

    function testSixteenRecipientsAndFifteenRemainderUnits() public view {
        uint256[] memory weights = new uint256[](16);
        for (uint256 i; i < 16; ++i) {
            weights[i] = 1;
        }
        uint256[] memory allocations = calculator.allocate(15, _recipients(16), weights);
        for (uint256 i; i < 16; ++i) {
            assertEq(allocations[i], i == 15 ? 0 : 1);
        }
        _assertOracle(type(uint256).max, _recipients(16), weights);
    }

    function testNearMaximumAmountsAndMaximumTotalWeight() public view {
        uint256 max = type(uint256).max;
        for (uint256 i; i < 16; ++i) {
            _assertOracle(max - i, _recipients(3), _three(1, 2, 3));
            _assertOracle(max - i, _recipients(3), _three(max - 3, 1, 2));
        }
        assertEq(calculator.allocate(max, _recipients(3), _three(max - 3, 1, 2)), _three(max - 3, 1, 2));
    }

    function testRejectsEmptyAndSeventeenRecipients() public view {
        _expect(
            1,
            _recipients(0),
            new uint256[](0),
            abi.encodeWithSelector(AllocationCalculator.InvalidRecipientCount.selector, 0)
        );
        _expect(
            1,
            _recipients(17),
            new uint256[](17),
            abi.encodeWithSelector(AllocationCalculator.InvalidRecipientCount.selector, 17)
        );
    }

    function testRejectsBothLengthMismatchDirections() public view {
        _expect(
            1,
            _recipients(3),
            new uint256[](2),
            abi.encodeWithSelector(AllocationCalculator.LengthMismatch.selector, 3, 2)
        );
        _expect(
            1,
            _recipients(2),
            new uint256[](3),
            abi.encodeWithSelector(AllocationCalculator.LengthMismatch.selector, 2, 3)
        );
    }

    function testRejectsZeroRecipientAtEveryIndex() public view {
        for (uint256 i; i < 3; ++i) {
            address[] memory recipients = _recipients(3);
            recipients[i] = address(0);
            _expect(
                1,
                recipients,
                _three(1, 2, 3),
                abi.encodeWithSelector(AllocationCalculator.ZeroRecipient.selector, i)
            );
        }
    }

    function testRejectsAdjacentAndNonAdjacentDuplicates() public view {
        for (uint256 i; i < 3; ++i) {
            for (uint256 j = i + 1; j < 3; ++j) {
                address[] memory recipients = _recipients(3);
                recipients[j] = recipients[i];
                _expect(
                    1,
                    recipients,
                    _three(1, 2, 3),
                    abi.encodeWithSelector(AllocationCalculator.DuplicateRecipient.selector, i, j)
                );
            }
        }
    }

    function testRejectsZeroWeightAtEveryIndex() public view {
        for (uint256 i; i < 3; ++i) {
            uint256[] memory weights = _three(1, 2, 3);
            weights[i] = 0;
            _expect(
                1,
                _recipients(3),
                weights,
                abi.encodeWithSelector(AllocationCalculator.ZeroWeight.selector, i)
            );
        }
    }

    function testRejectsOverflowingTotalEvenForZeroAmount() public view {
        _expect(
            0,
            _recipients(3),
            _three(type(uint256).max - 1, 1, 1),
            abi.encodeWithSelector(AllocationCalculator.TotalWeightOverflow.selector)
        );
        _expect(
            type(uint256).max,
            _recipients(3),
            _three(type(uint256).max, 1, 1),
            abi.encodeWithSelector(AllocationCalculator.TotalWeightOverflow.selector)
        );
    }

    function testRejectsEtherAndDoesNotTransfer() public {
        vm.deal(address(this), 1 ether);
        address[] memory recipients = _recipients(3);
        for (uint256 i; i < 3; ++i) {
            vm.deal(recipients[i], 17 + i);
        }
        bytes memory data = abi.encodeCall(calculator.allocate, (10, recipients, _three(1, 2, 3)));
        (bool success,) = address(calculator).call{value: 1}(data);
        assertTrue(!success);
        (success,) = address(calculator).call{value: 1}("");
        assertTrue(!success);
        calculator.allocate(10, recipients, _three(1, 2, 3));
        for (uint256 i; i < 3; ++i) {
            assertEq(recipients[i].balance, 17 + i);
        }
        assertEq(address(calculator).balance, 0);
    }

    function testFuzzConservationAndOrderingFullWidth(uint256 amount, uint256 seed, uint8 size) public view {
        uint256 count = 1 + uint256(size) % 16;
        uint256[] memory weights = new uint256[](count);
        uint256 budget = type(uint256).max - count;
        for (uint256 i; i < count; ++i) {
            uint256 extra = uint256(keccak256(abi.encode(seed, i))) % (budget + 1);
            weights[i] = extra + 1;
            budget -= extra;
        }
        _assertOracle(amount, _recipients(count), weights);
    }

    function testFuzzNativeProductReference(uint128 amount, uint64 a, uint64 b, uint64 c) public view {
        uint256[] memory weights = _three(uint256(a) + 1, uint256(b) + 1, uint256(c) + 1);
        uint256 total = weights[0] + weights[1] + weights[2];
        uint256[] memory expected = new uint256[](3);
        uint256[] memory remainder = new uint256[](3);
        uint256 allocated;
        for (uint256 i; i < 3; ++i) {
            uint256 product = uint256(amount) * weights[i];
            expected[i] = product / total;
            remainder[i] = product % total;
            allocated += expected[i];
        }
        bool[3] memory awarded;
        for (uint256 left = uint256(amount) - allocated; left > 0; --left) {
            uint256 winner = 3;
            for (uint256 i; i < 3; ++i) {
                if (!awarded[i] && (winner == 3 || remainder[i] > remainder[winner])) winner = i;
            }
            awarded[winner] = true;
            ++expected[winner];
        }
        assertEq(calculator.allocate(amount, _recipients(3), weights), expected);
    }

    function testFuzzPermutationWithoutRemainderTies(uint128 amount, uint64 a, uint64 b, uint64 c)
        public
        view
    {
        uint256[] memory weights = _three(uint256(a) + 1, uint256(b) + 1, uint256(c) + 1);
        uint256 total = weights[0] + weights[1] + weights[2];
        uint256 r0 = uint256(amount) * weights[0] % total;
        uint256 r1 = uint256(amount) * weights[1] % total;
        uint256 r2 = uint256(amount) * weights[2] % total;
        if (r0 == r1 || r0 == r2 || r1 == r2) return;
        address[] memory recipients = _recipients(3);
        uint256[] memory original = calculator.allocate(amount, recipients, weights);
        (recipients[0], recipients[2]) = (recipients[2], recipients[0]);
        (weights[0], weights[2]) = (weights[2], weights[0]);
        uint256[] memory permuted = calculator.allocate(amount, recipients, weights);
        assertEq(permuted, _three(original[2], original[1], original[0]));
    }

    function _assertOracle(uint256 amount, address[] memory recipients, uint256[] memory weights)
        internal
        view
    {
        uint256 total;
        for (uint256 i; i < weights.length; ++i) {
            total += weights[i];
        }
        uint256[] memory actual = calculator.allocate(amount, recipients, weights);
        assertEq(actual.length, weights.length);
        uint256[] memory remainders = new uint256[](weights.length);
        bool[] memory bonus = new bool[](weights.length);
        uint256 sum;
        for (uint256 i; i < weights.length; ++i) {
            (uint256 floor, uint256 remainder) = _referenceDivision(amount, weights[i], total);
            remainders[i] = remainder;
            assertTrue(actual[i] >= floor);
            assertTrue(actual[i] - floor <= 1);
            bonus[i] = actual[i] != floor;
            if (bonus[i]) assertTrue(remainder > 0);
            sum += actual[i];
        }
        assertEq(sum, amount);
        for (uint256 i; i < weights.length; ++i) {
            if (!bonus[i]) continue;
            for (uint256 j; j < weights.length; ++j) {
                if (bonus[j]) continue;
                assertTrue(remainders[i] > remainders[j] || (remainders[i] == remainders[j] && i < j));
            }
        }
    }

    /// @dev Independent binary long division: process bits of amount, maintaining
    /// prefix * weight = quotient * denominator + remainder. Uses no multiplication
    /// of full-width inputs, assembly, modular inverse, or mulmod.
    function _referenceDivision(uint256 amount, uint256 weight, uint256 denominator)
        internal
        pure
        returns (uint256 quotient, uint256 remainder)
    {
        for (uint256 bit = 256; bit > 0;) {
            --bit;
            quotient *= 2;
            if (remainder >= denominator - remainder) {
                remainder -= denominator - remainder;
                ++quotient;
            } else {
                remainder *= 2;
            }
            if ((amount >> bit) & 1 != 0) {
                if (remainder >= denominator - weight) {
                    remainder -= denominator - weight;
                    ++quotient;
                } else {
                    remainder += weight;
                }
            }
        }
    }

    function _expect(
        uint256 amount,
        address[] memory recipients,
        uint256[] memory weights,
        bytes memory reason
    ) internal view {
        (bool success, bytes memory actual) = address(calculator)
            .staticcall(abi.encodeCall(calculator.allocate, (amount, recipients, weights)));
        assertTrue(!success);
        assertTrue(keccak256(actual) == keccak256(reason));
    }

    function _recipients(uint256 count) internal pure returns (address[] memory recipients) {
        recipients = new address[](count);
        for (uint256 i; i < count; ++i) {
            recipients[i] = address(uint160(0x1001 + i));
        }
    }

    function _three(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory values) {
        values = new uint256[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FullMath} from "../src/FullMath.sol";
import {TestBase} from "./TestBase.sol";

contract FullMathHarness {
    function mulDiv(uint256 x, uint256 y, uint256 denominator) external pure returns (uint256) {
        return FullMath.mulDiv(x, y, denominator);
    }
}

contract FullMathTest is TestBase {
    FullMathHarness internal harness;

    function setUp() public {
        harness = new FullMathHarness();
    }

    function testMaximumProduct() public view {
        uint256 max = type(uint256).max;
        assertEq(harness.mulDiv(max, max, max), max);
        assertEq(harness.mulDiv(max, max - 1, max), max - 1);
    }

    function testPowerOfTwoDenominator() public view {
        assertEq(harness.mulDiv(type(uint256).max, 1 << 200, 1 << 255), (1 << 201) - 1);
        assertEq(harness.mulDiv(1 << 200, 1 << 100, 1 << 100), 1 << 200);
    }

    function testBorrowFromHighWord() public view {
        // Low word is zero and the nonzero remainder must borrow from the high word.
        assertEq(harness.mulDiv(1 << 128, 1 << 128, 3), type(uint256).max / 3);
    }

    function testZeroAndSmallProducts() public view {
        assertEq(harness.mulDiv(0, type(uint256).max, 1), 0);
        assertEq(harness.mulDiv(7, 5, 3), 11);
        assertEq(harness.mulDiv(9, 1, 1), 9);
    }

    function testRejectsZeroDenominatorForBothProductPaths() public {
        vm.expectRevert(abi.encodeWithSelector(FullMath.ZeroDenominator.selector));
        harness.mulDiv(0, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(FullMath.ZeroDenominator.selector));
        harness.mulDiv(type(uint256).max, type(uint256).max, 0);
    }

    function testRejectsQuotientOverflow() public {
        vm.expectRevert(abi.encodeWithSelector(FullMath.QuotientOverflow.selector));
        harness.mulDiv(type(uint256).max, type(uint256).max, type(uint256).max - 1);
        vm.expectRevert(abi.encodeWithSelector(FullMath.QuotientOverflow.selector));
        harness.mulDiv(1 << 128, 1 << 128, 1);
    }

    function testFuzzNativeProduct(uint128 x, uint128 y, uint256 denominator) public view {
        if (denominator == 0) denominator = 1;
        assertEq(harness.mulDiv(x, y, denominator), uint256(x) * uint256(y) / denominator);
    }
}

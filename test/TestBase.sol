// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface Vm {
    function chainId(uint256 chainId_) external;
    function deal(address account, uint256 balance) external;
    function expectRevert(bytes calldata revertData) external;
}

/// @dev Minimal local assertions and Foundry interface; no downloaded test dependencies.
abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint mismatch");
    }

    function assertEq(uint256[] memory actual, uint256[] memory expected) internal pure {
        require(actual.length == expected.length, "length mismatch");
        for (uint256 i; i < actual.length; ++i) {
            assertEq(actual[i], expected[i]);
        }
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "assertion failed");
    }
}

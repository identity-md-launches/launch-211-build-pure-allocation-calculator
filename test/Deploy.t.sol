// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Deploy} from "../script/Deploy.s.sol";
import {AllocationCalculator} from "../src/AllocationCalculator.sol";
import {TestBase} from "./TestBase.sol";

contract DeployTest is TestBase {
    Deploy internal deployer;

    function setUp() public {
        deployer = new Deploy();
    }

    function testDeploymentEnabledOnSepoliaWithNoConstructorArguments() public {
        vm.chainId(11155111);
        AllocationCalculator calculator = deployer.deploy(Deploy.Config({enabled: true}));
        assertTrue(address(calculator).code.length > 0);
        assertTrue(address(calculator).code.length <= 24_576);
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x1001);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        assertEq(calculator.allocate(type(uint256).max, recipients, weights)[0], type(uint256).max);
    }

    function testMainnetDeploymentRejected() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.WrongChain.selector, 1));
        deployer.deploy(Deploy.Config({enabled: true}));
    }

    function testLocalChainDeploymentRejectedByReleaseScript() public {
        vm.chainId(31337);
        vm.expectRevert(abi.encodeWithSelector(Deploy.WrongChain.selector, 31337));
        deployer.deploy(Deploy.Config({enabled: true}));
    }

    function testDisabledDeploymentRejected() public {
        vm.chainId(11155111);
        vm.expectRevert(abi.encodeWithSelector(Deploy.DeploymentDisabled.selector));
        deployer.deploy(Deploy.Config({enabled: false}));
    }

    function testRuntimeHasNoEscapeOrTransferOpcodes() public {
        vm.chainId(11155111);
        AllocationCalculator calculator = deployer.deploy(Deploy.Config({enabled: true}));
        bytes memory code = address(calculator).code;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            // No CALL, CALLCODE, DELEGATECALL, STATICCALL, CREATE, CREATE2, SELFDESTRUCT or SSTORE.
            assertTrue(op != 0xf1 && op != 0xf2 && op != 0xf4 && op != 0xfa);
            assertTrue(op != 0xf0 && op != 0xf5 && op != 0xff && op != 0x55);
        }
    }
}

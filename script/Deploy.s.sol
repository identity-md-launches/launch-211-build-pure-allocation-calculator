// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AllocationCalculator} from "../src/AllocationCalculator.sol";

interface DeploymentVm {
    function envOr(string calldata name, bool defaultValue) external returns (bool);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys only the calculator, only on Sepolia. Signer is supplied to Forge.
contract Deploy {
    DeploymentVm internal constant vm = DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 public constant TARGET_CHAIN_ID = 11155111;

    struct Config {
        bool enabled;
    }

    error DeploymentDisabled();
    error WrongChain(uint256 actual);

    function run() external returns (AllocationCalculator calculator) {
        Config memory config = Config({enabled: vm.envOr("DEPLOYMENT_ENABLED", true)});
        validate(config);
        vm.startBroadcast();
        calculator = deploy(config);
        vm.stopBroadcast();
    }

    /// @dev Tests pass config directly; no shared process environment is mutated.
    function deploy(Config memory config) public returns (AllocationCalculator calculator) {
        validate(config);
        calculator = new AllocationCalculator();
    }

    function validate(Config memory config) public view {
        if (!config.enabled) revert DeploymentDisabled();
        if (block.chainid != TARGET_CHAIN_ID) revert WrongChain(block.chainid);
    }
}

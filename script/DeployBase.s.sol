// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { MockToken } from "../src/MockToken.sol";

/// @notice Step 1 (Base Sepolia): deploy the mock USDC salary token.
/// Env: DEPLOYER_PRIVATE_KEY
/// Run it with the deploy helper in script/deploy.sh, see README.
contract DeployBase is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(pk);

        MockToken usdc = new MockToken("Mock USDC", "mUSDC", 6);

        vm.stopBroadcast();

        console.log("MockUSDC: ", address(usdc));
    }
}

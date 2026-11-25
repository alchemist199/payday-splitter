// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { PaydayReactive } from "../src/PaydayReactive.sol";

/// @notice Step 5b (Lasna): point the reactive contract at the vault, so its
/// callbacks go to the right place.
/// Env: DEPLOYER_PRIVATE_KEY, REACTIVE (Lasna PaydayReactive address),
///      VAULT (Base Sepolia PaydayVault address)
/// Run it with the deploy helper in script/deploy.sh, see README.
contract SetupDemoLasna is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        PaydayReactive reactive = PaydayReactive(payable(vm.envAddress("REACTIVE")));
        address vault = vm.envAddress("VAULT");

        vm.startBroadcast(pk);

        reactive.setRecipient(vault);

        vm.stopBroadcast();

        console.log("Recipient set to PaydayVault: ", vault);
    }
}

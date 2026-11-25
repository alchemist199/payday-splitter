// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { PaydayReactive } from "../src/PaydayReactive.sol";

/// @notice Step 3 (Lasna testnet): deploy the reactive contract, funded with
/// lREACT so it can pay for reactive transactions.
/// Env: DEPLOYER_PRIVATE_KEY, VAULT (Base Sepolia PaydayVault address)
/// VAULT must be the address of a vault that already exists. Deploy the vault
/// first (step 2), then the reactive, so the subscription points at a live
/// contract. Predict the reactive address before step 2, so the vault can name
/// it as its callback sender: run ./script/deploy.sh predict-reactive, then
/// deploy the vault with REACTIVE set to that address, then deploy here.
/// Run it with the deploy helper in script/deploy.sh, see README.
contract DeployLasna is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address vault = vm.envAddress("VAULT");
        vm.startBroadcast(pk);

        // Funding at deploy (payable constructor). Default 0.05 lREACT: a
        // triggering react() costs roughly 100k gas, so 0.05 covers several
        // paydays. Override with REACTIVE_FUNDING_WEI if needed.
        uint256 funding = vm.envOr("REACTIVE_FUNDING_WEI", uint256(0.05 ether));
        PaydayReactive reactive = new PaydayReactive{ value: funding }(84532, vault);

        vm.stopBroadcast();

        console.log("PaydayReactive: ", address(reactive));
        console.log("Subscribed to SalaryReceived on Base Sepolia vault: ", vault);
    }
}

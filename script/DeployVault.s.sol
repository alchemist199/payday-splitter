// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { PaydayVault } from "../src/PaydayVault.sol";

/// @notice Step 2 (Base Sepolia): deploy the PaydayVault callback contract.
/// Deploy this before the reactive contract, so the vault exists when the
/// reactive subscribes to it. REACTIVE must be the predicted reactive address:
/// run ./script/deploy.sh predict-reactive first, then deploy here with that
/// address, then deploy the reactive. Send no other Lasna transaction from the
/// deployer between predicting the reactive address and deploying it, or the
/// reactive will land at the wrong address.
/// Env: DEPLOYER_PRIVATE_KEY, REACTIVE (predicted Lasna PaydayReactive address),
///      TOKEN (Base Sepolia MockUSDC address),
///      SPENDING_BUCKET, SAVINGS_BUCKET, INVESTING_BUCKET (optional, set the
///      three bucket addresses now if you already know them)
/// Run it with the deploy helper in script/deploy.sh, see README.
contract DeployVault is Script {
    // Base Sepolia callback proxy (from Reactive docs).
    address payable internal constant CALLBACK_PROXY = payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585);

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address reactive = vm.envAddress("REACTIVE");
        address token = vm.envAddress("TOKEN");
        address spending = vm.envOr("SPENDING_BUCKET", address(0));
        address savings = vm.envOr("SAVINGS_BUCKET", address(0));
        address investing = vm.envOr("INVESTING_BUCKET", address(0));
        vm.startBroadcast(pk);

        PaydayVault vault = new PaydayVault(IPayable(CALLBACK_PROXY), reactive, token);
        if (spending != address(0) && savings != address(0) && investing != address(0)) {
            vault.setBuckets(spending, savings, investing);
        }

        vm.stopBroadcast();

        console.log("PaydayVault: ", address(vault));
        console.log("Callback proxy: ", CALLBACK_PROXY);
        console.log("Authorized reactive: ", reactive);
        console.log("Token: ", token);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { MockToken } from "../src/MockToken.sol";
import { PaydayVault } from "../src/PaydayVault.sol";

/// @notice Step 5a (Base Sepolia): mint 2000 mock USDC to the deployer,
/// approve the vault, and deposit 1000 as salary. The deposit emits
/// SalaryReceived, which is what the reactive contract watches for.
/// Env: DEPLOYER_PRIVATE_KEY, TOKEN (Base Sepolia MockUSDC address),
///      VAULT (Base Sepolia PaydayVault address)
/// Run it with the deploy helper in script/deploy.sh, see README.
contract SetupDemoBase is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        MockToken usdc = MockToken(vm.envAddress("TOKEN"));
        PaydayVault vault = PaydayVault(payable(vm.envAddress("VAULT")));

        vm.startBroadcast(pk);

        usdc.mint(deployer, 2000e6);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6);

        vm.stopBroadcast();

        console.log("Minted 2000 mUSDC to: ", deployer);
        console.log("Salary deposited: 1000 mUSDC");
        console.log("Pending salary in vault: ", vault.pendingSalary());
    }
}

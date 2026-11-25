// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { MockToken } from "../src/MockToken.sol";
import { PaydayVault } from "../src/PaydayVault.sol";
import { PaydayReactive } from "../src/PaydayReactive.sol";

address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
address constant CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
uint256 constant BASE_SEPOLIA = 84532;

/// @notice Stand-in for the Reactive system contract (etched at 0x8888...).
/// Records every callback request so tests can assert on it.
contract MockSystem {
    struct CallbackReq {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    CallbackReq[] public callbacks;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config) external {
        callbacks.push(CallbackReq(config.chainId, config.recipient, config.gasLimit, config.payload));
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function callbackCount() external view returns (uint256) {
        return callbacks.length;
    }
}

/// @notice Stand-in for the Base Sepolia callback proxy.
contract MockProxy is IPayable {
    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}

contract PaydaySplitterTest is Test {
    MockToken internal usdc;
    PaydayVault internal vault;
    PaydayReactive internal reactive;
    MockSystem internal system;
    MockProxy internal proxy;

    address internal employer = address(0xBEEF);
    address internal spending = address(0x1111);
    address internal savings = address(0x2222);
    address internal investing = address(0x3333);

    uint256 internal constant SALARY_1000 = 1000e6;
    uint256 internal constant SALARY_500 = 500e6;
    uint256 internal constant SALARY_50 = 50e6;

    function setUp() public {
        vm.warp(1_000_000);
        system = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(system).code);
        proxy = new MockProxy();

        usdc = new MockToken("Mock USDC", "mUSDC", 6);

        // The vault address must be known before the reactive contract is
        // deployed (it subscribes to the vault), and the vault needs the
        // reactive address (immutable callback sender). Predict the vault
        // address: the reactive contract is the next creation, the vault
        // the one after it.
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        reactive = new PaydayReactive{ value: 1 ether }(BASE_SEPOLIA, predictedVault);
        vault = new PaydayVault(IPayable(payable(address(proxy))), address(reactive), address(usdc));
        assertEq(address(vault), predictedVault);
        reactive.setRecipient(address(vault));

        vault.setBuckets(spending, savings, investing);
        vault.setPercentages(5000, 3000, 2000);

        usdc.mint(employer, 100_000e6);
        vm.startPrank(employer);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _deposit(uint256 amount) internal {
        vm.prank(employer);
        vault.deposit(amount);
    }

    function _salaryLog(address employee, uint256 amount) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: BASE_SEPOLIA,
            contractAddress: address(vault),
            topic0: uint256(keccak256("SalaryReceived(address,uint256,uint256)")),
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: abi.encode(employee, amount, vm.getBlockTimestamp()),
            blockNumber: block.number,
            opCode: 1,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _reactAsSystem(address employee, uint256 amount) internal {
        vm.prank(SYSTEM_ADDR);
        reactive.react(_salaryLog(employee, amount));
    }

    /// @notice The callback payload starts with the 4-byte selector; strip it before decoding the args.
    function _stripSelector(bytes memory payload) internal pure returns (bytes memory args) {
        args = new bytes(payload.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = payload[i + 4];
        }
    }

    function _deliverCallback(uint256 index) internal {
        (,,, bytes memory payload) = MockSystem(SYSTEM_ADDR).callbacks(index);
        (, uint256 amount, uint256 boost) =
            abi.decode(_stripSelector(payload), (address, uint256, uint256));
        vm.prank(address(proxy));
        vault.distribute(address(reactive), amount, boost);
    }

    function testFullLoopBigPaydayBoost() public {
        _deposit(SALARY_1000);
        assertEq(vault.pendingSalary(), SALARY_1000);
        _reactAsSystem(employer, SALARY_1000);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 1);
        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload) =
            MockSystem(SYSTEM_ADDR).callbacks(0);
        assertEq(chainId, BASE_SEPOLIA);
        assertEq(recipient, address(vault));
        assertGt(gasLimit, 0);
        (address injected, uint256 cbAmount, uint256 boost) =
            abi.decode(_stripSelector(payload), (address, uint256, uint256));
        assertEq(injected, address(0));
        assertEq(cbAmount, SALARY_1000);
        assertEq(boost, 1000);

        _deliverCallback(0);

        // 50/30/20 base plus 10 percent boost: 500 spending, 400 savings, 100 investing.
        assertEq(usdc.balanceOf(spending), 500e6);
        assertEq(usdc.balanceOf(savings), 400e6);
        assertEq(usdc.balanceOf(investing), 100e6);
        assertEq(vault.pendingSalary(), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function testNormalSplitNoBoost() public {
        _deposit(SALARY_500);
        _reactAsSystem(employer, SALARY_500);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 1);
        (,,, bytes memory payload) = MockSystem(SYSTEM_ADDR).callbacks(0);
        (,, uint256 boost) = abi.decode(_stripSelector(payload), (address, uint256, uint256));
        assertEq(boost, 0);
        _deliverCallback(0);
        assertEq(usdc.balanceOf(spending), 250e6);
        assertEq(usdc.balanceOf(savings), 150e6);
        assertEq(usdc.balanceOf(investing), 100e6);
        assertEq(vault.pendingSalary(), 0);
    }

    function testDistributeDirectBoostMath() public {
        _deposit(SALARY_1000);
        vm.prank(address(proxy));
        vault.distribute(address(reactive), SALARY_1000, 1000);
        assertEq(usdc.balanceOf(spending), 500e6);
        assertEq(usdc.balanceOf(savings), 400e6);
        assertEq(usdc.balanceOf(investing), 100e6);
    }

    function testDustGuardBelowMinSalary() public {
        _deposit(SALARY_50);
        _reactAsSystem(employer, SALARY_50);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 0);
        assertEq(vault.pendingSalary(), SALARY_50);
    }

    function testMinSalaryBoundaryTriggers() public {
        _deposit(100e6);
        _reactAsSystem(employer, 100e6);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 1);
    }

    function testBigPaydayBoundaryBoosts() public {
        _deposit(999e6);
        _reactAsSystem(employer, 999e6);
        (,,, bytes memory payload) = MockSystem(SYSTEM_ADDR).callbacks(0);
        (,, uint256 boost) = abi.decode(_stripSelector(payload), (address, uint256, uint256));
        assertEq(boost, 0);
    }

    function testCooldownBlocksSecondTrigger() public {
        _deposit(SALARY_1000);
        _reactAsSystem(employer, SALARY_1000);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 1);
        vm.warp(1_000_030);
        _reactAsSystem(employer, SALARY_1000);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 1);
        vm.warp(1_000_061);
        _reactAsSystem(employer, SALARY_1000);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 2);
    }

    function testDistributeNoOpOnZeroPending() public {
        assertEq(vault.pendingSalary(), 0);
        vm.prank(address(proxy));
        vault.distribute(address(reactive), SALARY_1000, 0);
        assertEq(usdc.balanceOf(spending), 0);
        assertEq(usdc.balanceOf(savings), 0);
        assertEq(usdc.balanceOf(investing), 0);
    }

    function testDistributeNoOpOnZeroAmount() public {
        _deposit(SALARY_500);
        vm.prank(address(proxy));
        vault.distribute(address(reactive), 0, 0);
        assertEq(vault.pendingSalary(), SALARY_500);
        assertEq(usdc.balanceOf(spending), 0);
    }

    function testDistributeCapsAtPending() public {
        _deposit(100e6);
        vm.prank(address(proxy));
        vault.distribute(address(reactive), SALARY_1000, 0);
        assertEq(usdc.balanceOf(spending), 50e6);
        assertEq(usdc.balanceOf(savings), 30e6);
        assertEq(usdc.balanceOf(investing), 20e6);
        assertEq(vault.pendingSalary(), 0);
    }

    function testDistributeRejectsBoostAboveInvesting() public {
        _deposit(SALARY_1000);
        vm.prank(address(proxy));
        vault.distribute(address(reactive), SALARY_1000, 2001);
        assertEq(usdc.balanceOf(spending), 0);
        assertEq(usdc.balanceOf(savings), 0);
        assertEq(usdc.balanceOf(investing), 0);
        assertEq(vault.pendingSalary(), SALARY_1000);
    }

    function testDistributeBoostEqualToInvestingOk() public {
        _deposit(SALARY_1000);
        vm.prank(address(proxy));
        vault.distribute(address(reactive), SALARY_1000, 2000);
        assertEq(usdc.balanceOf(spending), 500e6);
        assertEq(usdc.balanceOf(savings), 500e6);
        assertEq(usdc.balanceOf(investing), 0);
    }

    function testUnauthorizedDistributeReverts() public {
        _deposit(SALARY_500);
        vm.expectRevert();
        vault.distribute(address(reactive), SALARY_500, 0);
        vm.prank(address(proxy));
        vm.expectRevert();
        vault.distribute(address(0xDEAD), SALARY_500, 0);
        assertEq(vault.pendingSalary(), SALARY_500);
    }

    function testPercentagesMustSumTo10000() public {
        vm.expectRevert("percentages must sum to 10000");
        vault.setPercentages(5000, 3000, 1000);
        vm.expectRevert("percentages must sum to 10000");
        vault.setPercentages(6000, 3000, 2000);
        vault.setPercentages(4000, 4000, 2000);
        assertEq(vault.spendingBps(), 4000);
        assertEq(vault.savingsBps(), 4000);
        assertEq(vault.investingBps(), 2000);
    }

    function testOnlyOwnerCanSetConfig() public {
        vm.prank(employer);
        vm.expectRevert();
        vault.setPercentages(4000, 4000, 2000);
        vm.prank(employer);
        vm.expectRevert();
        vault.setBuckets(spending, savings, investing);
        vm.prank(employer);
        vm.expectRevert();
        reactive.setMinSalary(1);
    }

    function testWrongTopicIgnored() public {
        _deposit(SALARY_1000);
        IReactive.LogRecord memory log = _salaryLog(employer, SALARY_1000);
        log.topic0 = uint256(keccak256("SomethingElse(uint256)"));
        vm.prank(SYSTEM_ADDR);
        reactive.react(log);
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 0);
    }

    function testReactRevertsForNonSystem() public {
        vm.expectRevert();
        reactive.react(_salaryLog(employer, SALARY_1000));
    }

    function testReactSkipsWhenRecipientUnset() public {
        PaydayReactive fresh = new PaydayReactive{ value: 0.1 ether }(BASE_SEPOLIA, address(vault));
        vm.prank(SYSTEM_ADDR);
        fresh.react(_salaryLog(employer, SALARY_1000));
        assertEq(MockSystem(SYSTEM_ADDR).callbackCount(), 0);
    }

    function testDustStaysInVaultAndWithdrawable() public {
        // 101 units split 50/30/20 gives 50 + 30 + 20 = 100, dust is 1 unit.
        _deposit(101);
        vm.prank(address(proxy));
        vault.distribute(address(reactive), 101, 0);
        assertEq(vault.pendingSalary(), 0);
        assertEq(usdc.balanceOf(address(vault)), 1);
        vault.withdrawDust();
        assertEq(usdc.balanceOf(address(this)), 1);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function testSettersUpdateReactiveConfig() public {
        reactive.setMinSalary(200e6);
        reactive.setBigPaydayThreshold(2000e6);
        reactive.setSavingsBoostBps(500);
        reactive.setCooldown(120);
        assertEq(reactive.minSalary(), 200e6);
        assertEq(reactive.bigPaydayThreshold(), 2000e6);
        assertEq(reactive.savingsBoostBps(), 500);
        assertEq(reactive.cooldown(), 120);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PaydayReactive, the reactive contract (Lasna testnet).
/// @notice Subscribes to SalaryReceived events from the PaydayVault on Base
/// Sepolia. On each event it decides, it does not just pass through:
///   1. Dust guard: skip if the salary is below minSalary.
///   2. Big payday boost: if the salary is at or above bigPaydayThreshold,
///      add savingsBoostBps to the savings share (taken from investing).
///   3. Cooldown: do not re-trigger within N seconds of the last distribution.
/// If all pass, it requests a callback to distribute() on the vault.
/// react() never reverts as a filter: a revert is still billed, so unhealthy
/// logs just fall through. Cooldowns use block.timestamp, never block.number.
/// Note on decoding: the event has no indexed fields, so every field arrives
/// in the data as (address employee, uint256 amount, uint256 timestamp).
/// That also keeps the event a plain LOG1, so opCode is 1.
contract PaydayReactive is AbstractReactive, Ownable {
    uint256 public constant SALARY_RECEIVED_TOPIC0 = uint256(keccak256("SalaryReceived(address,uint256,uint256)"));
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    event DistributionRequested(address indexed employee, uint256 amount, uint256 boostSavingsBps);
    event RecipientUpdated(address recipient);
    event MinSalaryUpdated(uint256 minSalary);
    event BigPaydayThresholdUpdated(uint256 bigPaydayThreshold);
    event SavingsBoostUpdated(uint256 savingsBoostBps);
    event CooldownUpdated(uint256 cooldown);

    uint256 public immutable originChainId;
    address public immutable vault;
    address public recipient;

    uint256 public minSalary = 100e6;
    uint256 public bigPaydayThreshold = 1000e6;
    uint256 public savingsBoostBps = 1000;
    uint256 public cooldown = 60;
    uint256 public lastDistribution;

    constructor(uint256 originChainId_, address vault_) payable Ownable(msg.sender) {
        originChainId = originChainId_;
        vault = vault_;
        SYSTEM.subscribe(originChainId_, vault_, SALARY_RECEIVED_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function setRecipient(address recipient_) external onlyOwner {
        recipient = recipient_;
        emit RecipientUpdated(recipient_);
    }

    function setMinSalary(uint256 minSalary_) external onlyOwner {
        minSalary = minSalary_;
        emit MinSalaryUpdated(minSalary_);
    }

    function setBigPaydayThreshold(uint256 bigPaydayThreshold_) external onlyOwner {
        bigPaydayThreshold = bigPaydayThreshold_;
        emit BigPaydayThresholdUpdated(bigPaydayThreshold_);
    }

    function setSavingsBoostBps(uint256 savingsBoostBps_) external onlyOwner {
        require(savingsBoostBps_ <= 10000, "boost above 100 percent");
        savingsBoostBps = savingsBoostBps_;
        emit SavingsBoostUpdated(savingsBoostBps_);
    }

    function setCooldown(uint256 cooldown_) external onlyOwner {
        cooldown = cooldown_;
        emit CooldownUpdated(cooldown_);
    }

    /// @notice Settles outstanding debt to the system contract from this balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        if (log_.topic0 != SALARY_RECEIVED_TOPIC0 || log_.opCode != 1) return;
        if (recipient == address(0)) return;
        (address employee, uint256 amount,) = abi.decode(log_.data, (address, uint256, uint256));
        if (amount < minSalary) return;
        if (lastDistribution != 0 && block.timestamp < lastDistribution + cooldown) return;
        uint256 boost = amount >= bigPaydayThreshold ? savingsBoostBps : 0;
        lastDistribution = block.timestamp;
        bytes memory payload =
            abi.encodeWithSignature("distribute(address,uint256,uint256)", address(0), amount, boost);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: originChainId,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
        emit DistributionRequested(employee, amount, boost);
    }
}

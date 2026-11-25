// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title PaydayVault, the callback contract (Base Sepolia).
/// @notice Holds salary in mock USDC. The owner configures three buckets
/// (spending, savings, investing) and their percentages in basis points, once.
/// When salary lands, deposit() records it as pending and emits SalaryReceived.
/// The reactive contract on Lasna sees that event and requests a callback to
/// distribute(), which splits the pending salary to the buckets.
/// distribute() never reverts on bad input: it no-ops and emits SalarySkipped,
/// because a failed callback still bills the recipient. Rounding dust stays in
/// the vault balance, outside pending salary, and the owner can sweep it later.
/// Auth: only the callback proxy may call, and only for the authorized
/// reactive contract (both modifiers, always).
/// Note on the event: no indexed fields. The reactive system passes the log
/// opcode as opCode, and an event with one indexed field arrives as LOG2, not
/// LOG1. Keeping every field in the data keeps the event a plain LOG1, so the
/// reactive contract sees opCode 1 and decodes everything from the data.
contract PaydayVault is AbstractCallback, Ownable {
    event SalaryReceived(address employee, uint256 amount, uint256 timestamp);
    event SalaryDistributed(uint256 amount, uint256 spending, uint256 savings, uint256 investing);
    event SalarySkipped(uint256 requestedAmount, uint256 pendingAmount);
    event BucketsUpdated(address spendingBucket, address savingsBucket, address investingBucket);
    event PercentagesUpdated(uint256 spendingBps, uint256 savingsBps, uint256 investingBps);
    event DustWithdrawn(address indexed to, uint256 amount);

    uint256 public constant BPS_DENOMINATOR = 10000;

    IERC20 public immutable token;
    uint256 public pendingSalary;

    address public spendingBucket;
    address public savingsBucket;
    address public investingBucket;

    uint256 public spendingBps = 5000;
    uint256 public savingsBps = 3000;
    uint256 public investingBps = 2000;

    constructor(IPayable callbackProxy_, address callbackSender_, address token_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
        Ownable(msg.sender)
    {
        token = IERC20(token_);
    }

    /// @notice Accept salary into the vault. Anyone may deposit for any employee.
    function deposit(uint256 amount) external {
        require(amount > 0, "amount is zero");
        token.transferFrom(msg.sender, address(this), amount);
        pendingSalary += amount;
        emit SalaryReceived(msg.sender, amount, block.timestamp);
    }

    /// @notice Split pending salary to the three buckets. Called by the callback
    /// proxy; reactive_ is the address the proxy injected (the requesting contract).
    /// The boost moves savings share up and investing share down by the same bps.
    /// Rounding dust stays in the vault balance, outside pending salary, so the
    /// owner can sweep it later with withdrawDust().
    function distribute(address reactive_, uint256 amount, uint256 boostSavingsBps)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        uint256 pending = pendingSalary;
        if (pending == 0 || amount == 0) {
            emit SalarySkipped(amount, pending);
            return;
        }
        if (boostSavingsBps > investingBps) {
            emit SalarySkipped(amount, pending);
            return;
        }
        if (spendingBucket == address(0) || savingsBucket == address(0) || investingBucket == address(0)) {
            emit SalarySkipped(amount, pending);
            return;
        }
        uint256 effective = amount > pending ? pending : amount;
        uint256 spending = (effective * spendingBps) / BPS_DENOMINATOR;
        uint256 savings = (effective * (savingsBps + boostSavingsBps)) / BPS_DENOMINATOR;
        uint256 investing = (effective * (investingBps - boostSavingsBps)) / BPS_DENOMINATOR;
        uint256 distributed = spending + savings + investing;
        if (distributed == 0) {
            emit SalarySkipped(amount, pending);
            return;
        }
        pendingSalary = pending - effective;
        token.transfer(spendingBucket, spending);
        token.transfer(savingsBucket, savings);
        token.transfer(investingBucket, investing);
        emit SalaryDistributed(effective, spending, savings, investing);
    }

    /// @notice Set the three bucket addresses that receive the split.
    function setBuckets(address spendingBucket_, address savingsBucket_, address investingBucket_) external onlyOwner {
        require(spendingBucket_ != address(0), "spending bucket is zero");
        require(savingsBucket_ != address(0), "savings bucket is zero");
        require(investingBucket_ != address(0), "investing bucket is zero");
        spendingBucket = spendingBucket_;
        savingsBucket = savingsBucket_;
        investingBucket = investingBucket_;
        emit BucketsUpdated(spendingBucket_, savingsBucket_, investingBucket_);
    }

    /// @notice Set the split percentages in basis points. Must sum to 10000.
    function setPercentages(uint256 spendingBps_, uint256 savingsBps_, uint256 investingBps_) external onlyOwner {
        require(spendingBps_ + savingsBps_ + investingBps_ == BPS_DENOMINATOR, "percentages must sum to 10000");
        spendingBps = spendingBps_;
        savingsBps = savingsBps_;
        investingBps = investingBps_;
        emit PercentagesUpdated(spendingBps_, savingsBps_, investingBps_);
    }

    /// @notice Sweep leftover rounding dust (vault balance above pending salary) to the owner.
    function withdrawDust() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        uint256 dust = balance > pendingSalary ? balance - pendingSalary : 0;
        require(dust > 0, "no dust");
        token.transfer(msg.sender, dust);
        emit DustWithdrawn(msg.sender, dust);
    }

    /// @notice Settles outstanding callback debt from this contract's balance.
    function coverDebt() external {
        _coverDebt();
    }
}

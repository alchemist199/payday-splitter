# Payday Splitter

A paycheck router for the Reactive Omni Buildathon, Set It and Forget It track.

You set your split once. Every payday, when salary lands, the split happens on its own. No bot. No manual transaction.

## How it works

```
Base Sepolia (84532)                      Lasna (5318007)
┌──────────────────────┐                  ┌──────────────────────────┐
│ MockUSDC (6 dec)     │                  │ PaydayReactive         │
│ PaydayVault          │ SalaryReceived   │  (AbstractReactive)    │
│  · holds salary      │ ──event────────▶ │  · dust guard          │
│  · buckets + percent │                  │  · big payday boost    │
│  · distribute()      │ ◀── callback ─── │  · cooldown            │
│    (callback only)   │                  └──────────────────────────┘
└──────────────────────┘
```

1. The owner sets three buckets (spending, savings, investing) and their percentages in basis points. Default is 50, 30, 20.
2. Salary arrives. `deposit()` takes mock USDC into the vault, records it as pending, and emits `SalaryReceived`.
3. The reactive contract on Lasna sees the event. It skips dust below `minSalary` (default 100 USDC). It skips repeats inside the cooldown (default 60 seconds). If the salary is at or above `bigPaydayThreshold` (default 1000 USDC), it adds `savingsBoostBps` (default 1000, that is 10 percent) to the savings share, taken from investing.
4. If all checks pass, it requests a callback. The vault splits the pending salary to the three buckets and emits `SalaryDistributed`.

## Contracts

MockToken, Base Sepolia. Mintable ERC20 mock, 6 decimals, minter role.

PaydayVault, Base Sepolia. Holds salary, splits it on callback only.

PaydayReactive, Lasna. Watches SalaryReceived, decides, requests the callback.

Callback proxy on Base Sepolia: `0x476F44b11F5C942c58f4c8E3d0300E5710743585`

## Deployed, live and proven

MockUSDC on Base Sepolia: `0xb91542b7f5469a8bad988391152cfde02b524f08`

PaydayVault on Base Sepolia: `0xb316207d43cfda17948e080aE3fdc481Dc7e6C35`

PaydayReactive on Lasna: `0x70789afFDEfc198765B0553EF48a9E9C43d97B74`

The loop is proven on chain. A 1000 mock USDC salary was deposited
(tx `0x7629b078944ee65beeb2740ca929dc4e034973e73b1daade06922cd0d501162c`,
block 63435360) and the reactive contract split it on callback
(tx `0x6720216bee2774a4bfa5d001beb489d7190f9032af64f1a84b58a7c15b1e63cc`,
block 63435366): 500 spending, 400 savings, 100 investing. Full proof,
all deploy txs, and the two failed deployments before this one are in
`DEPLOYED.md`.

## Setup

You need Foundry. Then:

```
forge install
forge build
forge test
```

That is all.

## Deploy, in order

Set `DEPLOYER_PRIVATE_KEY` first. Create your own `.env` file in the repo
root with `DEPLOYER_PRIVATE_KEY=<your key>`, or export it in your shell.
The `.env` file is not in the repo and is never committed. The helper in
`script/deploy.sh` runs each step.

Order matters. The vault must exist before the reactive contract subscribes to it. So predict the reactive address first, deploy the vault with that address as its callback sender, then deploy the reactive. Send no other Lasna transaction from the deployer between predicting the reactive address and deploying it, or the reactive will land at the wrong address.

1. Deploy the mock token on Base Sepolia.
   `./script/deploy.sh base`
   Save the MockUSDC address as `TOKEN`.
2. Predict the reactive address on Lasna.
   `./script/deploy.sh predict-reactive`
   Save it as `REACTIVE`. The vault in the next step names this address as its callback sender, and the reactive lands here in step 3.
3. Deploy the vault on Base Sepolia.
   `./script/deploy.sh vault`
   Set the three bucket addresses first if you know them. Use `SPENDING_BUCKET`, `SAVINGS_BUCKET`, `INVESTING_BUCKET`. If you skip them, call `setBuckets()` on the vault after deploy.
4. Deploy the reactive contract on Lasna.
   `./script/deploy.sh lasna`
   It subscribes to the vault, which already exists. It is funded with 0.05 lREACT at deploy. Override with `REACTIVE_FUNDING_WEI` if you need less.
5. Point the reactive contract at the vault.
   `./script/deploy.sh setup-lasna`
6. Fill in the addresses in `frontend/config.js`.

Use `./script/deploy.sh predict-reactive` to predict the reactive address.
Do not use any other prediction command.

## Demo

1. Send the demo salary.
   `./script/deploy.sh setup-base`
   This mints 2000 mock USDC to the deployer, approves the vault, and deposits 1000 as salary.
2. Watch the vault. The reactive contract sees `SalaryReceived`, 1000 USDC is a big payday, so it requests the callback with a 10 percent savings boost.
3. The vault splits it: 500 spending, 400 savings, 100 investing. That is 300 plus 100 boost for savings, and 200 minus 100 boost for investing.
4. Open `frontend/index.html` to see the split config, the bucket balances, and the loop history live. The Send salary button there does the same deposit from the browser.

## Safety notes

`distribute()` only runs for the callback proxy, and only for the authorized reactive contract. Both checks apply every time.

`distribute()` never reverts on bad input. Zero pending, zero amount, a boost bigger than the investing share, or missing buckets all end in a no-op with a `SalarySkipped` event. A failed callback still bills the recipient, so a no-op is cheaper than a revert.

`react()` never reverts as a filter. A wrong topic, a wrong op code, or an unset recipient just returns early.

The vault re-checks the pending amount on chain before it splits anything, and it caps the split at the pending balance. Rounding dust stays in the vault balance, outside pending salary. The owner can sweep it with `withdrawDust()`.

Percentages must sum to 10000 basis points. `setPercentages()` enforces that.

Cooldowns use `block.timestamp`, never block number.

## Small differences from the first design

Two details changed while building, both for honest reasons.

First, `SalaryDistributed` has no employee field. The callback payload carries only the amount and the boost, so the vault has no way to know which employee the salary came from. The event carries the amount and the three shares instead.

Second, when the requested amount is bigger than the pending balance, `distribute()` caps at the pending balance and splits that. The first design said no-op in that case, but capping matches the vault re-checking on chain and is what the tests cover.

Third, dust accounting. The first design said dust stays pending. That made `withdrawDust()` useless, because dust counted as pending could never be swept. Now pending drops by the full split amount, dust stays in the vault balance outside pending, and the owner can sweep it.

Fourth, the event has no indexed fields. The first version indexed the employee. An event with one indexed field is a LOG2, and the reactive system passes its opcode as 2, so the reactive contract saw opCode 2 and returned early on its opCode 1 check. The split never fired. Keeping every field in the data keeps the event a plain LOG1, so opCode is 1 and the reactive contract decodes the employee, the amount, and the timestamp from the data. The Liquidation Guardian does the same: its PriceUpdated event has no indexed fields.

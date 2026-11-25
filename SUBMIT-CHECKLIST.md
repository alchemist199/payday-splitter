# Payday Splitter, submit checklist

Track: Set It and Forget It. Buildathon: Reactive Omni Buildathon.
The user submits this himself on DoraHacks. Do not submit for him.

## What to paste in the form

Project name: Payday Splitter

One line: Set your paycheck split once, and every payday the split happens
on its own, on chain, with no bot and no manual transaction.

Repo: USER STEP. Push the local repo in ~/workspace/reactive-omni-buildathon/set-it-and-forget-it/ to GitHub as a public repo first, then paste the repo link here. The repo is ready: contracts, tests, frontend, README, DEPLOYED.md.

Demo video: USER STEP. Upload the video file in the work dir (see below) and paste the link. It is under 3 minutes.

## Contracts

Origin chain: Base Sepolia (84532).
Reactive chain: Lasna (5318007).

- MockUSDC (Base Sepolia): 0xb91542b7f5469a8bad988391152cfde02b524f08
- PaydayVault (Base Sepolia): 0xb316207d43cfda17948e080aE3fdc481Dc7e6C35
- PaydayReactive (Lasna): 0x70789afFDEfc198765B0553EF48a9E9C43d97B74
- Callback proxy (Base Sepolia): 0x476F44b11F5C942c58f4c8E3d0300E5710743585

## The loop, proof

Demo salary: 1000 mock USDC. Big payday, so savings gets the 10 percent boost.

- Deposit tx (Base Sepolia, block 63435360): 0x7629b078944ee65beeb2740ca929dc4e034973e73b1daade06922cd0d501162c
- Callback tx (Base Sepolia, block 63435366, 6 blocks later): 0x6720216bee2774a4bfa5d001beb489d7190f9032af64f1a84b58a7c15b1e63cc
- SalaryDistributed event in the callback tx: amount 1000, spending 500, savings 400, investing 100.
- Bucket balances after: spending 3500, savings 400, investing 100, vault pending 0.

## Deploy txs

- MockUSDC deploy: 0x25357866bce90fb94c54b03b0a4b5522d8f50f32e440271afa7557e4bec4f593 (block 63425276)
- Vault deploy: 0x62a1eb4deb4554485066cf0be2c9e12b84add9a9f23fe73b3d91389f7e9fb363 (block 63434811)
- Set buckets: 0x6ccfd4eb90e9e7d446d13ca2e254e6275000f5002da385a71a119e073f0a09de (block 63434811)
- Reactive deploy: 0x3adb5202634a764b2a10bbbe2281ebf29595828e96317c3ddf58e2794ad08487 (Lasna block 9216271)
- Set recipient: 0x77514934593f14d8e6835e789d21ed8e64c3bf11d49c854476005b62eaa14cbb (Lasna block 9216296)

The reactive contract subscribes to SalaryReceived in its constructor, so
there is no separate subscription tx. The deploy tx is the subscription.
The loop proof above is the evidence it is live.

Source verification on the explorers is optional. The contracts are in
`src/` in the repo. The callback proxy is a Reactive system contract, not
ours, so it has no deploy tx from us.

## How it works, short

1. The owner sets three buckets (spending, savings, investing) and their
   percentages. Default is 50, 30, 20.
2. Salary arrives. `deposit()` takes mock USDC into the vault and emits
   `SalaryReceived`.
3. The reactive contract on Lasna sees the event. It skips dust below 100
   USDC and repeats inside the 60 second cooldown. At or above 1000 USDC
   it adds a 10 percent savings boost, taken from investing.
4. It requests a callback. The vault splits the pending salary to the three
   buckets and emits `SalaryDistributed`.

## Files in the work dir

- README.md: full docs, a stranger can follow it.
- DEPLOYED.md: all addresses, all tx hashes, the loop proof, and the two
  failed deployments before this one.
- IDEA.md: why this idea is different from the other builders.
- frontend/: demo page with the real addresses in config.js.
- Video: payday-splitter-demo.mp4 in the work dir (under 3 minutes).

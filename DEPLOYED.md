# Payday Splitter, deployed state

Status: the full loop works on testnet. A 1000 mock USDC salary deposited
in the vault on Base Sepolia was split by the reactive contract on Lasna
into 500 spending, 400 savings, 100 investing. Deposit tx and callback tx
are below. This file records what is live, what failed before, and the proof.

## What is built

20 tests pass. `forge build` is clean. No double hyphen and no em dash in any file.

## Deployment v3, live and proven

Built from the fixed contracts. The salary event has no indexed fields, so
it is a plain LOG1 and opCode is 1. The reactive contract decodes the
employee, the amount, and the timestamp from the data. The deploy order was
predict reactive, deploy vault, deploy reactive, so the reactive landed at
the predicted address and subscribed to a vault that already existed.

- MockUSDC, Base Sepolia: 0xb91542b7f5469a8bad988391152cfde02b524f08 (same token, reused)
  - Deploy tx: 0x25357866bce90fb94c54b03b0a4b5522d8f50f32e440271afa7557e4bec4f593 (block 63425276)
- PaydayVault v3, Base Sepolia: 0xb316207d43cfda17948e080aE3fdc481Dc7e6C35
  - Deploy tx: 0x62a1eb4deb4554485066cf0be2c9e12b84add9a9f23fe73b3d91389f7e9fb363 (block 63434811)
  - Set buckets tx: 0x6ccfd4eb90e9e7d446d13ca2e254e6275000f5002da385a71a119e073f0a09de (block 63434811)
  - Buckets: spending 0x2B5C2f695046766a124AcB1544C56dC2bb6b139C, savings 0x81c38946289B1d6E9C23eb16f077a0fcf85D95fD, investing 0x375e0B5da806D9f52A3fF50EEDCcC9cCd71e169b
  - Percentages: 5000, 3000, 2000. Min salary 100 USDC, big payday at 1000 USDC, savings boost 1000 bps, cooldown 60 seconds.
- PaydayReactive v3, Lasna: 0x70789afFDEfc198765B0553EF48a9E9C43d97B74
  - Deploy tx: 0x3adb5202634a764b2a10bbbe2281ebf29595828e96317c3ddf58e2794ad08487 (block 9216271)
  - Funded with 0.01 lREACT at deploy. Subscribed to SalaryReceived on the v3 vault.
  - Recipient set to the v3 vault, tx: 0x77514934593f14d8e6835e789d21ed8e64c3bf11d49c854476005b62eaa14cbb (block 9216296)

## The loop, proven

Demo salary of 1000 mock USDC, a big payday, so savings gets the 10 percent boost.

- Mint tx: 0xeaa8eb37f5e7d880a69437f9d8e331219bea555e32c2b75d5fdb4ce9e08a785d (block 63435360)
- Approve tx: 0xfa88d48d739222bc1dafb3bc7b7a6df95e8110d8bab7e3d7544c3b9c2753eb02 (block 63435360)
- Deposit tx: 0x7629b078944ee65beeb2740ca929dc4e034973e73b1daade06922cd0d501162c (block 63435360)
- Callback tx: 0x6720216bee2774a4bfa5d001beb489d7190f9032af64f1a84b58a7c15b1e63cc (block 63435366, 6 blocks later)
- SalaryDistributed event in the callback tx: amount 1000, spending 500, savings 400, investing 100.
- Bucket balances after: spending 3500 (3000 before split plus 500), savings 400, investing 100, vault pending 0.
- Why spending is 3500, not 500: the spending bucket is the deployer address itself. It held 2000 mock USDC from earlier demo rounds before this demo. The demo minted 2000 more and deposited 1000, so it held 3000 before the split, then received the 500 split share. Verified on chain: balance 2000 at block 63435359, 3000 at block 63435360, 3500 at block 63435366.

## Funds

- The deployer got 0.1 SepETH on Base Sepolia from the user, then sent 0.0008 SepETH to the Reactive faucet, tx 0x12643fac455688d9c70a3a6bbb526918ad5f2045e7e25737642847e84983d774, which added 0.08 lREACT on Lasna. A second send of 0.0005 SepETH, tx 0x23b664e2d96da3e3a45fd62413dc8577b1f2e6a00f3aa66b8dae925fd6f82817, added 0.05 lREACT for margin.
- Deployer Lasna balance before the v3 deploy: 0.1562982 lREACT. After the reactive deploy: 0.0590971 lREACT. The deploy cost 0.0972011 lREACT (872011 gas at 100 gwei plus 0.01 funding). The reactive contract holds 0.01 lREACT of funding, so the loop can run again. The deployer still holds 0.059 lREACT for further testing.
- The Reactive faucet on Base Sepolia is 0x2afaFD298b23b62760711756088F75B7409f5967. Send SepETH to it and it sends lREACT to the sender on Lasna. Rate is 1 SepETH to 100 lREACT. Do not send more than 5 SepETH in one transaction.
- The 0.1 SepETH the user sent first landed on Ethereum Sepolia by mistake, so it was not used. No bridge was needed. The user sent a second 0.1 SepETH directly on Base Sepolia.

## Deployment v1, superseded

Built from the first contracts. The salary event indexed the employee, so it was a LOG2 and the reactive contract saw opCode 2 and returned early on its opCode 1 check. Two demo deposits never split. The reactive contract spent about 0.011 lREACT per deposit and never requested a callback.

- MockUSDC, Base Sepolia: 0xb91542b7f5469a8bad988391152cfde02b524f08
- PaydayVault v1, Base Sepolia: 0xFb2F1f2CEf902B82759A305d4A52D91Ac4b7b394
- PaydayReactive v1, Lasna: 0xae6253ed6050cf93359c7780c2e0f434765b532b
- Deposit 1 tx: 0x55b68080ee2b50e15710bf550f44b74f3ffe954e2301205d05aeaa9f2eed52f9
- Deposit 2 tx: 0x90ce02ea51e16c1a12716291b312b46462930a0e2ba7f80668bc08d9c9f5f784
- Vault v1 holds 2000 mock USDC pending. It will not split. Leave it alone.

## Deployment v2, superseded

Built from the fixed contracts. The salary event has no indexed fields, so it is a plain LOG1 and opCode is 1. The reactive contract decodes the employee, the amount, and the timestamp from the data.

The vault deployed at the wrong address. I predicted the vault address, then sent a faucet transaction on Base Sepolia before deploying the vault, and the faucet transaction spent the nonce the vault was predicted for. The vault landed at 0x605483e8ee659be4649f63b3b593bca2dd5269a0 instead of the predicted 0x7f7c40c09B86811709fC9CbC0238AF6952Cec1dE. The reactive contract subscribed to the predicted address, which does not exist, so it will never see an event from the real vault.

- MockUSDC, Base Sepolia: 0xb91542b7f5469a8bad988391152cfde02b524f08 (same token, reused)
- PaydayVault v2, Base Sepolia: 0x605483e8ee659be4649f63b3b593bca2dd5269a0
  - Deploy tx: 0x7a02ed7027347c3d66b77e24dc8bac0f62022506ddd87402a6b8d6fd1823ff77
  - Set buckets tx: 0xce88257f4826aec2df5f308e5c216b523d1f736bf652cf1cc99053f94d5fba58
  - Buckets: spending 0x2B5C2f695046766a124AcB1544C56dC2bb6b139C, savings 0x81c38946289B1d6E9C23eb16f077a0fcf85D95fD, investing 0x375e0B5da806D9f52A3fF50EEDCcC9cCd71e169b
  - Percentages: 5000, 3000, 2000. Empty, no salary deposited yet.
- PaydayReactive v2, Lasna: 0x2c2badfa86c65cb23544597b03b3b3a80949941e
  - Deploy tx: 0x9f243cbd3c655def3d56bbf41b65f9e74b88a0251d1ae5cfe1043d9a73843124
  - Funded with 0.01 lREACT. Subscribed to 0x7f7c40c09B86811709fC9CbC0238AF6952Cec1dE, which does not exist. Do not use it.

## Networks

- Base Sepolia, chain 84532, RPC https://sepolia.base.org. Callback proxy 0x476F44b11F5C942c58f4c8E3d0300E5710743585.
- Lasna, chain 5318007, RPC https://lasna-rpc.rnk.dev/. Gas price 100 gwei. System contract 0x8888888888888888888888888888888888888888.

## Deployer

0x2B5C2f695046766a124AcB1544C56dC2bb6b139C. Its private key lives in the
author's local `.env` file, which is not in the repo and is never committed.
To redeploy, set `DEPLOYER_PRIVATE_KEY` in your own `.env` or shell.

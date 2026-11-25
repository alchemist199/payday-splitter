# Payday Splitter IDEA

## The idea

A "set it and forget it" paycheck router. You set your split rules once
(e.g. 50% spending / 30% savings / 20% investing), then forget it. Every
payday, when salary lands, the reactive contract sees it and the split
happens automatically, on-chain, with no bot and no manual transaction.

Story: everyone gets paid. Everyone manually splits their paycheck. This
removes that chore forever.

## Why it is different

Checked against every known build in this buildathon and the track brief:

- NOT a portfolio tracker (the blog's example). No portfolio, no tracking.
- NOT an LP price alert (the blog's example). No liquidity position.
- NOT custom rebalancing rules (the blog's example). No rebalancing, no
  portfolio weights. This routes incoming income, it does not manage holdings.
- NOT liquidation protection. That is the user's Liquidation Guardian
  (Every Second Counts track). Different track, different problem, different
  contracts.
- NOT Ramon Cortez's `personal-automation-reactive` (Medium, Nov 11, 2026).
  That is a generic event-driven automation prototype: it compiles in Remix,
  flips an `alertTriggered` boolean, and shows no live on-chain loop. Ours is
  a concrete product with a real money flow and a verified on-chain loop.
- NOT a stop-loss / take-profit. Those belong to the Every Second Counts
  track (the blog lists them there). This is income routing, not trading.
- NOT a DCA bot. No DEX swap, no price-based buying. The trigger is a
  salary deposit event, not a price.

## How it works

```
Base Sepolia (84532)                      Lasna (5318007)
┌──────────────────────┐                  ┌──────────────────────────┐
│ MockUSDC (6 dec)     │                  │ PaydayReactive         │
│ PaydayVault          │ SalaryReceived   │  (AbstractReactive)    │
│  · holds salary      │ ──event────────▶ │  · dust guard          │
│  · buckets + %       │                  │  · big-payday boost    │
│  · distribute()      │ ◀── callback ─── │  · cooldown            │
│    (callback only)   │                  └──────────────────────────┘
└──────────────────────┘
```

- `PaydayVault` (Base Sepolia, `AbstractCallback`): holds salary in mock
  USDC. Owner configures three buckets (spending, savings, investing) and
  their percentages in basis points. `deposit()` accepts salary and emits
  `SalaryReceived`. `distribute()` is callback-only (reactive contract via
  callback proxy): splits the pending salary to the buckets, emits
  `SalaryDistributed`. Safety: re-checks the pending amount on-chain, no-ops
  when nothing is pending, caps at the available balance.
- `PaydayReactive` (Lasna, `AbstractReactive`): subscribes to
  `SalaryReceived`. On each event it decides, it does not just pass through:
  1. Dust guard: skip if the salary is below `minSalary`.
  2. Big-payday boost: if the salary is at or above `bigPaydayThreshold`,
     add a configured bonus to the savings share (taken from investing).
  3. Cooldown: do not re-trigger within N seconds of the last distribution.
  If all pass, it requests a callback to `distribute()` with the amount and
  the savings boost. `react()` never reverts as a filter.

## Demo (under 3 minutes)

1. Owner sets the split: 50% spending / 30% savings / 20% investing.
   minSalary 100 USDC, bigPayday 1000 USDC, savings boost 10%.
2. Employer sends 1000 mock USDC salary to the vault (deposit tx).
3. Lasna reactive contract sees `SalaryReceived`, amount 1000, big payday,
   requests the callback.
4. Vault distributes: spending 500, savings 400 (300 + 100 boost),
   investing 100 (200 - 100 boost).
5. Show the three bucket balances before and after.

## Why it wins the track

- Usefulness: payday splitting is a chore every salaried person knows.
  The question "is this something you'd actually leave running?" answers
  itself: yes, every payday, forever.
- Integration: the reactive contract does real work (dust guard, boost
  decision, cooldown), not a bolted-on trigger. Without it the user must
  call `distribute()` by hand every payday.
- Execution: a real on-chain loop, deposit tx to callback tx, with tx
  hashes as proof.
- Craft: small readable contracts, a simple frontend, docs a stranger can
  follow.

## Network

Set It and Forget It may use Reactive mainnet or Lasna (blog: only Every
Second Counts must use Lasna). We use Lasna testnet, same as the
Liquidation Guardian, so no mainnet funds are spent. Origin chain is Base
Sepolia (mock USDC + vault), reactive chain is Lasna.

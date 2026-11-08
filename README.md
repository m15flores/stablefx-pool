# StableFX Pool

A constant-product AMM for a single EUR/USD stablecoin pair (USDC/EURC), built for cross-currency payments: pay an exact EUR amount from a USD balance, or convert an exact USD amount, with slippage and deadline protection.

[![CI](https://github.com/m15flores/stablefx-pool/actions/workflows/ci.yml/badge.svg)](https://github.com/m15flores/stablefx-pool/actions)
![Solidity](https://img.shields.io/badge/solidity-0.8.34-363636)
![License](https://img.shields.io/badge/license-MIT-blue)

> **Status: unaudited.** Built as a portfolio project.

Live on Arbitrum Sepolia: [`StableFXPool`](https://sepolia.arbiscan.io/address/0xC0cC17B4cAc20F1A389f764bE6F51fe8b3CA3b32#code) (verified).

## Why

A company holding USD stablecoins has to pay a EUR invoice of exactly €10,000. It needs to know two things: how much USD that costs, and that it will not pay more than expected.

StableFX Pool gives it two ways to swap, depending on what is fixed:

- **`swapExactOutput`**: "I need exactly 10,000 EURC." The pool charges whatever USDC that takes and reverts if it exceeds `amountInMax_`. This is the invoice case.
- **`swapExactInput`**: "I want to convert exactly 10,000 USDC." The pool sends back as much EURC as the reserves allow and reverts if it is below `amountOutMin_`.

`getAmountIn` and `getAmountOut` quote both directions without sending a transaction, so a backend can show the price before it submits anything.

The pool is deliberately small: one fixed pair, no factory, no router, no token sorting. Fewer moving parts means a smaller attack surface and code that is easy to read end to end.

## Deployments

Arbitrum Sepolia (chain ID 421614), verified. The pair is the real USDC and a mock EURC, because Circle's EURC is not available on that network.

| Contract | Address |
|---|---|
| `StableFXPool` | [`0xC0cC17B4cAc20F1A389f764bE6F51fe8b3CA3b32`](https://sepolia.arbiscan.io/address/0xC0cC17B4cAc20F1A389f764bE6F51fe8b3CA3b32#code) |
| `MockEURC` | [`0xD8ee702FE5AAc9165Fe7E70A407040c671694aA9`](https://sepolia.arbiscan.io/address/0xD8ee702FE5AAc9165Fe7E70A407040c671694aA9#code) |
| USDC | [`0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d`](https://sepolia.arbiscan.io/address/0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d) |
| Example swap (tx) | [`0xd4417b…d86d7b`](https://sepolia.arbiscan.io/tx/0xd4417bd215f04821eab02b03a670e600b96782a29cbae0084772beb374d86d7b) |

<details>
<summary>Notes on the deployment</summary>

- The pool is seeded with 15 USDC and about 13.04 MockEURC (a 1.15 rate). It demonstrates the mechanics, not a deep market. The [price impact](#price-impact) table shows the depth a real payment needs.
- The example swap is a `swapExactOutput`: it paid 1.246111 USDC for exactly 1 EURC, about 8.4% above the 1.15 rate, which is what a 13 EURC pool costs.
- `MockEURC` lives in `script/mocks/` because it is the one that goes on-chain. Its `mint` is public on purpose, so anyone can get tokens to try the pool. Tests and the price impact script use a separate `MockERC20` in `test/mocks/`, which is never deployed.

</details>

## How it works

Constant product: `reserve0 × reserve1 = k`. A swap moves the reserves along that curve. Design choices:

| Choice | Why |
|---|---|
| 5 bps fee on the input | Stays in the pool and accrues to liquidity providers |
| Rounding favours the pool | `getAmountOut` rounds down, `getAmountIn` rounds up, so `k` never decreases |
| First 1000 LP shares locked at `0x…dEaD` | Blocks the first-depositor inflation attack |
| Prices from internal reserves, not `balanceOf` | Tokens donated to the pool cannot move the price |
| Raw units, decimals never read | A 6-decimal and an 18-decimal token can be paired |
| `deadline_`, min/max amount, recipient check, `nonReentrant` | Protection on every state-changing call |

## API

Full NatSpec and errors in [`IStableFXPool`](src/interfaces/IStableFXPool.sol).

| Function | What it does |
|---|---|
| `swapExactOutput(tokenOut_, amountOut_, amountInMax_, to_, deadline_)` | Receive exactly `amountOut_`; pay what it takes, up to `amountInMax_` |
| `swapExactInput(tokenIn_, amountIn_, amountOutMin_, to_, deadline_)` | Pay exactly `amountIn_`; receive at least `amountOutMin_` |
| `getAmountIn` / `getAmountOut` | Quotes without sending a transaction |
| `addLiquidity` / `removeLiquidity` | Deposit or withdraw both tokens, with LP shares |
| `getReserves`, `token0`, `token1` | Pool state |

## Tests

**92 tests, 100% coverage**

```text
╭----------------------+-------------------+-------------------+-----------------+-----------------╮
| File                 | % Lines           | % Statements      | % Branches      | % Funcs         |
+==================================================================================================+
| src/StableFXPool.sol | 100.00% (115/115) | 100.00% (158/158) | 100.00% (42/42) | 100.00% (13/13) |
|----------------------+-------------------+-------------------+-----------------+-----------------|
| Total                | 100.00% (115/115) | 100.00% (158/158) | 100.00% (42/42) | 100.00% (13/13) |
╰----------------------+-------------------+-------------------+-----------------+-----------------╯
```

| Type | Tests | What it proves |
|---|---|---|
| Unit | 81 | Every function and custom error, both swap directions, on 1:1 and 4:1 pools |
| Fuzz | 6 | 1000 runs each: `k` never decreases, round trips never profit, quotes match executed swaps |
| Attack | 2 | First-depositor inflation and direct donation fail |
| Mainnet fork | 3 | Real USDC and EURC: invoice payment, round trip, and a Circle blacklist freezing the pool |

<details>
<summary>Run them</summary>

```bash
forge test                                            # everything (fork tests skipped without an RPC)
forge test --match-contract StableFXPoolAttackTest    # attack tests only
forge test --match-test testFuzz                      # fuzz tests only
forge coverage --no-match-coverage "(test|script)" --report summary

# Fork tests, with any Ethereum mainnet RPC URL (set MAINNET_FORK_BLOCK to pin a block)
MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com forge test --match-contract StableFXPoolForkTest -vv
```

</details>

## Price impact

Cost of the €10,000 invoice from the example (11,500 USDC at a spot of 1.15), fee included:

| Pool reserves (EURC / USDC) | USDC paid | Impact vs spot |
|---|---|---|
| 100,000 / 115,000 | 12,784.17 | 11.17% |
| 1,000,000 / 1,150,000 | 11,621.97 | 1.06% |
| 10,000,000 / 11,500,000 | 11,517.27 | 0.15% |

Rule of thumb: impact is roughly the payment divided by the reserve. The pool has no oracle, so it follows the market only while arbitrageurs keep it there.

Reproduce it (plus a 50,000 EURC pool) with `forge script script/PriceImpact.s.sol -vv`.

## Security

**Unaudited.** The [Tests](#tests) section lists what is covered. Rounding favours the pool, `k` never decreases, state changes happen before transfers, every state-changing function is `nonReentrant`, and transfers use OpenZeppelin `SafeERC20`.

Known limitations:

- **No oracle.** The price is whatever the reserves say, and the first liquidity provider sets it. EUR/USD is not 1:1.
- **Custody risk.** The pool holds real stablecoins, so it inherits the issuer's powers: Circle can pause the tokens or blacklist an address, including the pool. The fork tests show it on the real USDC: once the pool is blacklisted, swaps and withdrawals revert.
- **Unsupported tokens.** Fee-on-transfer and rebasing tokens break the internal accounting.
- **Locked donations.** Tokens sent directly to the pool stay there. There is no `skim` or `sync`.
- **Raw units.** No decimal normalisation, so the price reflects the raw ratio of the reserves.

## Development

Requires [Foundry](https://book.getfoundry.sh/).

```bash
git clone --recurse-submodules https://github.com/m15flores/stablefx-pool
cd stablefx-pool
forge build
forge test
```

Scripts in `script/`:

- `PriceImpact.s.sol`: simulation only, prints the price impact table above.
- `Deploy.s.sol`: deploys `MockEURC` and `StableFXPool` and seeds the pool.

## Future work

- Invariant tests with a handler contract.
- A factory with token sorting, so the pool is not limited to a single pair.
- A backend service that indexes `SwapTokens` and exposes quotes over an API.

## License

MIT
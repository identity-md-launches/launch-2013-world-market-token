# World Market Token

WORLD is an immutable, fixed-supply ERC-20. Its constructor mints the entire supply to the immediate deployer in one mint operation. It uses the vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation.

| Property | Value |
| --- | --- |
| Solidity contract | `WorldMarketToken` |
| Source | `src/WorldMarketToken.sol` |
| Name | `World Market Token` |
| Symbol | `WORLD` |
| Decimals | `18` |
| Supply in WORLD | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10**27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Initial recipient | `msg.sender`, the immediate deployer |
| Administrator / owner | None |

## Behavior and assumptions

- Transfers deliver exactly the requested amount. The token has no transfer tax, rebase, burn function, lock, pause, blacklist, seizure, or upgrade mechanism.
- The only mint is in the constructor. Neither the deployer nor any other address can mint again or change the metadata or supply. `INITIAL_SUPPLY` exposes the fixed amount in smallest units.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with ERC-6093 custom errors on failure. Zero-value transfers between valid addresses and self-transfers are supported. Transfers to the zero address and approvals to a zero spender revert.
- `approve` replaces the current allowance. Finite allowances decrease when spent; `type(uint256).max` is an unlimited allowance and does not decrease. Even the deployer requires an allowance to transfer another holder's tokens.
- Minting and transfers emit `Transfer`; explicit approvals emit `Approval`. Spending an allowance in this OpenZeppelin version does not emit `Approval`, so integrations should read `allowance` for its current value.
- Ordinary ERC-20 behavior is assumed because no additional transfer rules were requested. The token makes no external calls, including during construction or transfers, and has no oracle, signature service, or other runtime dependency.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x95373f933c207b4217dab1963a7166a6523c03e45e26ed4f841163582123ab1b forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26 and the Cancun EVM target, enables optimization with 200 runs, and sets `bytecode_hash = "none"`. Fuzz tests use 1,024 cases each; stateful invariants use 256 sequences of 128 operations, with unexpected reverts treated as failures. Tests use isolated local state and require no RPC, environment lookups, keys, FFI, or filesystem cheatcodes. The shell seed above selects reproducible fuzz inputs; it is not read by contract/test code.

All Solidity dependencies and their licenses are ordinary files under `lib/`; no installation or network access is needed to build when the pinned compiler is installed. `remappings.txt` resolves them locally. Each dependency's `UPSTREAM.md` records its release and archive hash; `SHA256SUMS` records the unmodified source hashes. The production dependency is the ERC-20 subset of OpenZeppelin Contracts v5.0.2; forge-std v1.9.6 is test support.

The delivered tests cover deployment and metadata, exact transfers and allowances, events, invalid recipients and insufficient balances/allowances, failed-operation rollback, factory deployment and distribution, unavailable administrative selectors, and randomized conservation of balances and allowances. Local distribution tests model the token movements; the network's separate protected harness supplies the real Uniswap v4 integration checks.

## Deployment parameters

Deploy the creation bytecode for `src/WorldMarketToken.sol:WorldMarketToken` with no arguments and no ETH. The build artifact is `out/WorldMarketToken.sol/WorldMarketToken.json`. There are no external library links or initialization calls. The intended launch chain is Ethereum (chain ID 1); the constructor needs no pre-existing contracts or chain configuration.

When the launch factory creates the token, the factory receives all `10**27` units. A direct deployment gives them to the direct deployer instead. No owner or recipient parameter is needed: this is the requested deployer-mint behavior. No application contracts are part of this deliverable.

The separate launch process is responsible for preparing its manifest, deploying, and distributing the factory's balance. Per the supplied launch terms, 10% goes to the launch distributor, 80% seeds the pool, and 10% goes to the requester at `0x5440356760c390720d32992f58d0a4b31ce8c85c`. Those transfers are performed by the factory after construction. The token itself does not reserve allocations or create a pool.

The supplied pool terms are the Ethereum IMD pair at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, fee `12500` (1.25%), tick spacing `60`, and opening market capitalization `3600000000000000000000` in the pair's smallest units. The supplied provenance price is `79228162514264337593543950336`; the launch process derives the actual opening price from the supply, market capitalization, and deployed token address. These values are launch inputs, not token constructor parameters. This repository does not supply a launch manifest or broadcast transactions.

## After launch

There are no owner settings, privileged keys, keepers, or maintenance transactions. The launch operator should verify the deployed bytecode and public metadata, check that the constructor minted the full supply to the factory, and confirm the subsequent distribution and pool setup. Source publication and the independent release review belong to the launch process.

Holders control their transfers and allowances. They must verify recipient addresses and spender contracts, manage or revoke allowances, and account for the standard ERC-20 allowance replacement race (revoke and confirm before setting a new allowance when appropriate). Unlimited approval grants ongoing spending authority. Tokens sent to the token contract or another contract without a withdrawal path cannot be recovered by an administrator; there is no rescue function. Ordinary ETH transfers are rejected.

Foundry checks and the local code review are recorded in `SECURITY.md`. They do not replace an independent production security review.

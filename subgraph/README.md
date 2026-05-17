# DeFi Super-App — Subgraph

Indexes protocol events from the four event-emitting contracts (`AMM`,
`LendingPool`, `YieldVault`, `AchievementNFT`) and exposes them as a
queryable GraphQL endpoint.

## Layout

```
subgraph/
├── subgraph.yaml      # manifest — data sources, ABIs, event → handler map
├── schema.graphql     # 6 entities: Swap, LiquidityEvent, LoanPosition,
│                      #   VaultEvent, Achievement, ProtocolMetric
├── networks.json      # per-network address + startBlock (CLI flag --network)
├── src/
│   ├── shared.ts      # ProtocolMetric singleton + eventId helper
│   ├── amm.ts         # Swapped / LiquidityAdded / LiquidityRemoved
│   ├── lending.ts     # CollateralDeposited / CollateralWithdrawn /
│   │                  #   Borrowed / Repaid / Liquidated / InterestAccrued
│   ├── vault.ts       # Deposited / Withdrawn / YieldHarvested
│   └── nft.ts         # AchievementMinted
├── abis/              # JSON ABIs copied from out/<Contract>.sol/<Contract>.json
├── package.json
└── QUERIES.md         # 5 documented queries with sample responses
```

## Prerequisites

```bash
npm install -g @graphprotocol/graph-cli
```

## One-time setup

After running `./script/deploy.sh` (Phase 1), populate the manifest:

1. Open `deployments/421614.json` (chainId of Arbitrum Sepolia).
2. Copy each contract address into the matching `dataSources[].source.address`
   in `subgraph.yaml`, **and** into `networks.json`.
3. Set `startBlock` to the block in which `Deploy.s.sol` was broadcast
   (you can find it via `cast tx <deploy-tx> --json | jq .blockNumber`).
4. Copy fresh ABIs from the compiled contracts:

   ```bash
   for c in AMM LendingPool YieldVault AchievementNFT; do
     jq '.abi' "../out/${c}.sol/${c}.json" > "abis/${c}.json"
   done
   ```

## Build

```bash
npm install
npm run codegen   # generates TypeScript types from ABIs + schema
npm run build     # compiles AssemblyScript → WASM
```

`codegen` writes everything under `generated/` (gitignored).

## Deploy to The Graph Studio

1. Create a subgraph at <https://thegraph.com/studio/> named `defi-super-app`.
2. Copy the deploy key shown in the Studio UI.
3. From this directory:

   ```bash
   graph auth <DEPLOY_KEY>
   npm run deploy
   ```

4. The Studio dashboard will show the query URL — paste it into the
   frontend's `frontend/js/config.js` as `SUBGRAPH_URL`, and into the
   root `.env` as `SUBGRAPH_URL` (used by the README addresses table).

## Local development

```bash
docker compose up graph-node ipfs postgres   # or use Graph Node docs
npm run create-local
npm run deploy-local
```

## Generating sample traffic

After deployment, the simplest way to populate the subgraph is to use the
frontend to swap, deposit, and borrow — the indexer picks up events within
~30 seconds.

## Schema quick reference

See [QUERIES.md](./QUERIES.md) for five documented queries and sample
responses. The frontend consumes **Query 1** (recent swaps) and pulls
governance proposals from a separate on-chain read (the Governor doesn't
emit a list-friendly event we'd want to index).

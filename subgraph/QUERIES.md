# Subgraph Queries

Five documented GraphQL queries against the `defi-super-app` subgraph.
Each one has the use case, the query, and a sample response shape.

The frontend uses **Query 1** (Active proposals page) and **Query 5** (Recent swaps panel).

---

## 1. Recent swaps — `recentSwaps`

**Use case**: Render the "Recent activity" panel on the Swap page.

```graphql
query RecentSwaps($limit: Int = 20) {
  swaps(first: $limit, orderBy: blockTimestamp, orderDirection: desc) {
    id
    user
    tokenIn
    tokenOut
    amountIn
    amountOut
    blockTimestamp
    transactionHash
  }
}
```

Sample response:

```json
{
  "data": {
    "swaps": [
      {
        "id": "0xabc...01",
        "user": "0xfa...",
        "tokenIn": "0xWETH...",
        "tokenOut": "0xUSDC...",
        "amountIn": "1000000000000000000",
        "amountOut": "2000000000",
        "blockTimestamp": "1740009600",
        "transactionHash": "0xabc..."
      }
    ]
  }
}
```

---

## 2. User loan position — `loanByUser`

**Use case**: Lending page reads the user's live position from the subgraph rather than calling the contract repeatedly.

```graphql
query LoanByUser($user: Bytes!) {
  loanPosition(id: $user) {
    user
    collateral
    debt
    lastEvent
    lastUpdate
  }
}
```

Returns `null` if the user has never interacted with `LendingPool`.

---

## 3. Top liquidity providers — `topLpsByVolume`

**Use case**: Leaderboard widget; aggregates each provider's lifetime ADD contributions.

```graphql
query TopLps($limit: Int = 10) {
  liquidityEvents(
    first: 1000
    where: { action: ADD }
    orderBy: blockTimestamp
    orderDirection: desc
  ) {
    provider
    amountA
    amountB
    lpAmount
  }
}
```

Client-side, group by `provider` and sum `lpAmount` to rank. (The subgraph
schema is intentionally event-grained for auditability; aggregation lives
outside.)

---

## 4. Vault activity for an address — `vaultEventsByUser`

**Use case**: Vault page transaction history.

```graphql
query VaultEventsByUser($user: Bytes!, $limit: Int = 50) {
  vaultEvents(
    first: $limit
    where: { user: $user }
    orderBy: blockTimestamp
    orderDirection: desc
  ) {
    id
    action
    assets
    shares
    blockTimestamp
    transactionHash
  }
}
```

`action` is one of `DEPOSIT | WITHDRAW | YIELD_HARVEST`.

---

## 5. Achievements for an address — `achievementsByUser`

**Use case**: Profile widget showing badges earned.

```graphql
query AchievementsByUser($user: Bytes!) {
  achievements(where: { recipient: $user }, orderBy: blockTimestamp, orderDirection: desc) {
    tokenId
    achievementType
    tier
    blockTimestamp
  }
}
```

`achievementType` and `tier` are enum indices (see `AchievementNFT.sol`).

---

## 6. Active proposals — `proposals` (drives the Govern page)

**Use case**: The Governor page lists indexed proposals; each row's _state_ is
resolved live via `Governor.state(proposalId)` on-chain (state is dynamic and
should not be cached in the subgraph).

```graphql
query Proposals {
  proposals(first: 20, orderBy: createdAt, orderDirection: desc) {
    id
    proposalId
    description
    proposer
    voteStart
    voteEnd
    createdAt
  }
}
```

---

## Bonus: Global protocol metrics — `protocolMetric`

Used to render the homepage stats banner.

```graphql
query ProtocolMetrics {
  protocolMetric(id: "global") {
    totalSwaps
    totalLiquidityEvents
    totalVaultDeposits
    totalLoansOpened
    totalLiquidations
    totalAchievements
  }
}
```

// Thin GraphQL fetch wrapper for The Graph.

import { SUBGRAPH_URL } from "./config.js";

export async function gql(query, variables = {}) {
  const res = await fetch(SUBGRAPH_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) {
    throw new Error(`Subgraph HTTP ${res.status}`);
  }
  const json = await res.json();
  if (json.errors?.length) {
    throw new Error(`Subgraph: ${json.errors[0].message}`);
  }
  return json.data;
}

// ── Saved queries ──────────────────────────────────────────────────────────

export const Q_RECENT_SWAPS = `
  query RecentSwaps($limit: Int = 20) {
    swaps(first: $limit, orderBy: blockTimestamp, orderDirection: desc) {
      id user tokenIn tokenOut amountIn amountOut blockTimestamp transactionHash
    }
  }
`;

export const Q_PROPOSALS = `
  query Proposals {
    proposals(first: 20, orderBy: createdAt, orderDirection: desc) {
      id proposalId description proposer voteStart voteEnd createdAt
    }
  }
`;

export const Q_VAULT_EVENTS = `
  query VaultEventsByUser($user: Bytes!, $limit: Int = 50) {
    vaultEvents(
      first: $limit,
      where: { user: $user },
      orderBy: blockTimestamp,
      orderDirection: desc
    ) {
      id action assets shares blockTimestamp transactionHash
    }
  }
`;

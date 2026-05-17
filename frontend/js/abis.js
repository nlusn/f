// Minimal ABI fragments — only what the frontend actually calls.
// Full ABIs live under ../../out/<Contract>.sol/<Contract>.json.

export const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

export const PROTOCOL_TOKEN_ABI = [
  ...ERC20_ABI,
  "function getVotes(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
  "function delegate(address delegatee)",
];

export const AMM_ABI = [
  "function reserveA() view returns (uint256)",
  "function reserveB() view returns (uint256)",
  "function getAmountOut(address tokenIn, uint256 amountIn) view returns (uint256)",
  "function getSpotPrice() view returns (uint256 priceAinB, uint256 priceBinA)",
  "function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address to, uint256 deadline) returns (uint256)",
];

export const VAULT_ABI = [
  ...ERC20_ABI,
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function convertToShares(uint256 assets) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
];

export const LENDING_ABI = [
  "function positions(address) view returns (uint256 collateral, uint256 debt, uint256 debtPrincipal, uint256 lastAccrualTime)",
  "function healthFactor(address) view returns (uint256)",
  "function maxBorrow(address) view returns (uint256)",
  "function pendingInterest(address) view returns (uint256)",
  "function depositCollateral(uint256 amount)",
  "function withdrawCollateral(uint256 amount)",
  "function borrow(uint256 amount)",
  "function repay(uint256 amount)",
];

export const GOVERNOR_ABI = [
  "function state(uint256 proposalId) view returns (uint8)",
  "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
  "function proposalSnapshot(uint256 proposalId) view returns (uint256)",
  "function proposalDeadline(uint256 proposalId) view returns (uint256)",
  "function quorum(uint256 blockNumber) view returns (uint256)",
  "event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)",
];

/** Governor.state() enum values. */
export const PROPOSAL_STATE = [
  "Pending",
  "Active",
  "Canceled",
  "Defeated",
  "Succeeded",
  "Queued",
  "Expired",
  "Executed",
];

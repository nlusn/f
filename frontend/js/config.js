// =============================================================================
// frontend/js/config.js
//
// Edit the addresses below after running ./script/deploy.sh.
// Source of truth: deployments/<chainId>.json
// =============================================================================

/** Base Sepolia. */
export const CHAIN = {
  id: 84532,
  hexId: "0x14a34",
  name: "Base Sepolia",
  rpcUrl: "https://sepolia.base.org",
  explorer: "https://sepolia.basescan.org",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
};

/**
 * Contract addresses — paste from deployments/421614.json after deploying.
 * Leaving zero addresses lets the UI render but every write call will fail
 * with a clear "Contract not configured" error.
 */
export const ADDRESSES = {
  protocolToken: "0x4cda6882392D0D6c3B8fAd999ae26fAA3203b3b8",
  achievementNft: "0xCa6f8b712F396c94EF2fdB05320aBBd7602cF5D8",
  amm: "0xeD03483511cd41Ba895BE5c04B3AF1a215B58D23",
  lpToken: "0xf51717FFD2c41Be7dA36B024e8d49f28ea48822B",
  lendingPool: "0xc02E02e7552DAE658725db323c23f727890698dd",
  yieldVault: "0xe6baA064DCFD11bd64c09B2c0af51433270e8771",
  factory: "0xD60207Cb90008A649AdB11B453ebCeea689350f3",
  treasury: "0x9C12d97cd5bDB60Fc8203C619781D3B12F47E59D",
  timelock: "0x1d047ff66A75bD11537d727baEf31712a06FCf5d",
  governor: "0x93c023fAe0F268644af1A6e686A6ABc06096688a",
  // Mock pair tokens deployed via DeployMocks.s.sol (WETH / USDC mocks).
  tokenA: "0xE556d3960Ca66B8b90e6eA7A22B5c1140174860D",
  tokenB: "0xAA3D6C984BCe402e8Cf9320A77edB006262CA67c",
  borrowToken: "0xAA3D6C984BCe402e8Cf9320A77edB006262CA67c",
};

/** Token symbols for nicer rendering — purely cosmetic, override if you want. */
export const TOKEN_META = {
  tokenA: { symbol: "WETH", decimals: 18 },
  tokenB: { symbol: "USDC", decimals: 18 }, // mock USDC uses default OZ ERC20 (18 dec)
};

/** The Graph Studio query URL — Base Sepolia, b-ch-t-2-final-project v0.0.1. */
export const SUBGRAPH_URL =
  "https://api.studio.thegraph.com/query/1753431/b-ch-t-2-final-project/v0.0.1";

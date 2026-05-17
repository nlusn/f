# DeFi Super-App

[![CI](https://img.shields.io/badge/CI-passing-success)](.github/workflows/ci.yml)
[![Solidity](https://img.shields.io/badge/solidity-0.8.24-blue)](foundry.toml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A full-stack decentralised protocol implementing **Option A** of the
BCHT2 capstone:

> AMM + lending protocol + tokenised yield vault (ERC-4626), priced via
> Chainlink, governed by an on-chain DAO with a 2-day Timelock, indexed via
> The Graph, deployed to an L2 testnet.

## Components

| Layer        | Tech                                                       |
| ------------ | ---------------------------------------------------------- |
| Contracts    | Foundry · Solidity 0.8.24 · OpenZeppelin 5.x               |
| Governance   | Governor + TimelockController + ERC20Votes (1-day delay, 1-week period, 4% quorum, 1% threshold, 2-day timelock) |
| Oracles      | Chainlink price feeds with staleness guard                 |
| Upgradeable  | UUPS proxy for Treasury (V1 → V2 documented)               |
| Indexing     | The Graph subgraph (7 entities, 6 documented queries)      |
| Frontend     | Plain HTML/CSS/JS + ethers v6 + MetaMask                   |
| Deployment   | Base Sepolia                                           |
| CI           | GitHub Actions: build · test · coverage ≥ 90% · slither · solhint · prettier · subgraph build |

## Live deployment (Base Sepolia)

Addresses are written by `Deploy.s.sol` to `deployments/84532.json` after
broadcast. Once deployed, fill the table below with the verified Basescan
links.

| Contract        | Address                                                                                                                                | Basescan |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| ProtocolToken   | [`0x4cda6882392D0D6c3B8fAd999ae26fAA3203b3b8`](https://sepolia.basescan.org/address/0x4cda6882392D0D6c3B8fAd999ae26fAA3203b3b8#code)   | ✅ verified |
| AchievementNFT  | [`0xCa6f8b712F396c94EF2fdB05320aBBd7602cF5D8`](https://sepolia.basescan.org/address/0xCa6f8b712F396c94EF2fdB05320aBBd7602cF5D8#code)   | ✅ verified |
| AMM             | [`0xeD03483511cd41Ba895BE5c04B3AF1a215B58D23`](https://sepolia.basescan.org/address/0xeD03483511cd41Ba895BE5c04B3AF1a215B58D23#code)   | ✅ verified |
| LP Token        | [`0xf51717FFD2c41Be7dA36B024e8d49f28ea48822B`](https://sepolia.basescan.org/address/0xf51717FFD2c41Be7dA36B024e8d49f28ea48822B#code)   | ✅ verified |
| LendingPool     | [`0xc02E02e7552DAE658725db323c23f727890698dd`](https://sepolia.basescan.org/address/0xc02E02e7552DAE658725db323c23f727890698dd#code)   | ✅ verified |
| YieldVault      | [`0xe6baA064DCFD11bd64c09B2c0af51433270e8771`](https://sepolia.basescan.org/address/0xe6baA064DCFD11bd64c09B2c0af51433270e8771#code)   | ✅ verified |
| ProtocolFactory | [`0xD60207Cb90008A649AdB11B453ebCeea689350f3`](https://sepolia.basescan.org/address/0xD60207Cb90008A649AdB11B453ebCeea689350f3#code)   | ✅ verified |
| Treasury proxy  | [`0x9C12d97cd5bDB60Fc8203C619781D3B12F47E59D`](https://sepolia.basescan.org/address/0x9C12d97cd5bDB60Fc8203C619781D3B12F47E59D#code)   | ✅ verified |
| TreasuryV1 impl | [`0xc0679B318F4c4311653851DF8c630272a73427Bf`](https://sepolia.basescan.org/address/0xc0679B318F4c4311653851DF8c630272a73427Bf#code)   | ✅ verified |
| TreasuryV2 impl | [`0xF38dADFAC13b0EF1FDcAB1c0dBD546C2D3E2B99c`](https://sepolia.basescan.org/address/0xF38dADFAC13b0EF1FDcAB1c0dBD546C2D3E2B99c#code)   | ✅ verified |
| Timelock        | [`0x1d047ff66A75bD11537d727baEf31712a06FCf5d`](https://sepolia.basescan.org/address/0x1d047ff66A75bD11537d727baEf31712a06FCf5d#code)   | ✅ verified |
| Governor        | [`0x93c023fAe0F268644af1A6e686A6ABc06096688a`](https://sepolia.basescan.org/address/0x93c023fAe0F268644af1A6e686A6ABc06096688a#code)   | ✅ verified |
| Mock WETH (TOKEN_A) | [`0xE556d3960Ca66B8b90e6eA7A22B5c1140174860D`](https://sepolia.basescan.org/address/0xE556d3960Ca66B8b90e6eA7A22B5c1140174860D)  | mock     |
| Mock USDC (TOKEN_B) | [`0xAA3D6C984BCe402e8Cf9320A77edB006262CA67c`](https://sepolia.basescan.org/address/0xAA3D6C984BCe402e8Cf9320A77edB006262CA67c)  | mock     |
| Mock ETH/USD feed   | [`0x59B25EB71C4654e9AC7D6ee6e0D65a631D941a12`](https://sepolia.basescan.org/address/0x59B25EB71C4654e9AC7D6ee6e0D65a631D941a12)  | mock     |
| Mock USDC/USD feed  | [`0xB40A88db5EE5BC0193DAfb68Fd5a38241307cEc9`](https://sepolia.basescan.org/address/0xB40A88db5EE5BC0193DAfb68Fd5a38241307cEc9)  | mock     |

Subgraph (Base Sepolia, v0.0.1): [`https://api.studio.thegraph.com/query/1753431/b-ch-t-2-final-project/v0.0.1`](https://api.studio.thegraph.com/query/1753431/b-ch-t-2-final-project/v0.0.1) · [Studio dashboard](https://thegraph.com/studio/subgraph/b-ch-t-2-final-project/)

## Quick start

```bash
# 1. clone with submodules
git clone --recurse-submodules https://github.com/<you>/defi-super-app.git
cd defi-super-app

# 2. test
forge install
forge test -vvv
forge coverage --report summary

# 3. deploy (fills deployments/<chainId>.json + verifies on Basescan)
cp .env.example .env
$EDITOR .env       # set PRIVATE_KEY + token / feed addresses
./script/deploy.sh

# 4. subgraph
cd subgraph
npm install
# update addresses + startBlock in subgraph.yaml from deployments/<id>.json
npm run codegen && npm run build
graph auth <DEPLOY_KEY>
npm run deploy
cd ..

# 5. frontend
$EDITOR frontend/js/config.js     # paste addresses + subgraph URL
npx serve frontend                 # → http://localhost:3000
```

## Repository layout

```
src/         — Solidity contracts 
test/        — unit / fuzz / invariant / fork tests 
script/      — Deploy.s.sol, VerifyDeployment.s.sol, deploy.sh 
subgraph/    — schema, manifest, mappings 
frontend/    — HTML/CSS/JS dApp 
.github/     — CI workflow 
deployments/ — broadcast JSON outputs
```


## Security posture

- Every privileged function is `onlyRole`-gated with OpenZeppelin AccessControl.
- After deployment **no EOA has admin rights** — every protocol contract's
  `DEFAULT_ADMIN_ROLE` is held by the Timelock; deployer roles are
  renounced inside `Deploy.s.sol`.
- Chainlink price feeds revert on staleness (`ChainlinkPriceOracle.sol`).
- AMM, LendingPool, YieldVault use `ReentrancyGuard` on every state-changing
  external function (CEI pattern enforced — see audit report).
- All ERC-20 calls go through `SafeERC20`.
- ETH transfers use `call{value:}` with success check; no `transfer` / `send`.

The post-deployment script `VerifyDeployment.s.sol` asserts these properties
and writes the report to `deployments/verification-report.txt`.


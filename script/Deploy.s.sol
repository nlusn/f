// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AMM} from "../src/amm/AMM.sol";
import {LendingPool} from "../src/lending/LendingPool.sol";
import {YieldVault} from "../src/vault/YieldVault.sol";
import {ProtocolToken} from "../src/token/ProtocolToken.sol";
import {AchievementNFT} from "../src/nft/AchievementNFT.sol";
import {ProtocolFactory} from "../src/factory/ProtocolFactory.sol";
import {TreasuryV1} from "../src/treasury/TreasuryV1.sol";
import {TreasuryV2} from "../src/treasury/TreasuryV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock ERC-20 used as testnet tokens.
contract MockERC20 is Script {
    // Included for reference only; real mock is in test helpers.
}

/// @title Deploy
/// @notice Foundry broadcast script that deploys the entire DeFi Super-App to a target network.
///
/// Usage:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url arbitrum_sepolia \
///     --broadcast \
///     --verify \
///     -vvvv
///
/// Required environment variables:
///   PRIVATE_KEY            — deployer private key with 0x prefix (e.g. 0xabc123...)
///   TOKEN_A                — address of first AMM token  (or zero to deploy mock)
///   TOKEN_B                — address of second AMM token (or zero to deploy mock)
///   COLLATERAL_TOKEN       — collateral token for lending pool
///   BORROW_TOKEN           — borrow token for lending pool
///   COLLATERAL_PRICE_FEED  — Chainlink ETH/USD feed address
///   BORROW_PRICE_FEED      — Chainlink USD/USD (or stablecoin) feed address
///
/// Arbitrum Sepolia Chainlink feeds (as of 2025):
///   ETH/USD  0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
///   BTC/USD  0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69
///   LINK/USD 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298
contract Deploy is Script {
    // ─── Deployed addresses (populated at run time) ───────────────────────────

    ProtocolToken  public protocolToken;
    AchievementNFT public achievementNft;
    AMM            public amm;
    LendingPool    public lendingPool;
    YieldVault     public yieldVault;
    ProtocolFactory public factory;
    TreasuryV1     public treasury;  // points to proxy

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        address tokenA           = vm.envOr("TOKEN_A", address(0));
        address tokenB           = vm.envOr("TOKEN_B", address(0));
        address collateralToken  = vm.envOr("COLLATERAL_TOKEN", address(0));
        address borrowToken      = vm.envOr("BORROW_TOKEN", address(0));
        address collateralFeed   = vm.envOr("COLLATERAL_PRICE_FEED", address(0));
        address borrowFeed       = vm.envOr("BORROW_PRICE_FEED", address(0));

        vm.startBroadcast(deployerKey);

        // 1. Protocol token ──────────────────────────────────────────────────
        protocolToken = new ProtocolToken(deployer);
        console2.log("ProtocolToken  :", address(protocolToken));

        // 2. Achievement NFT ─────────────────────────────────────────────────
        achievementNft = new AchievementNFT(deployer);
        console2.log("AchievementNFT :", address(achievementNft));

        // 3. AMM ─────────────────────────────────────────────────────────────
        // Caller must supply real token addresses; testnet deployments pass
        // the already-deployed mock token addresses.
        require(tokenA != address(0) && tokenB != address(0), "Deploy: set TOKEN_A and TOKEN_B");
        amm = new AMM(tokenA, tokenB);
        console2.log("AMM            :", address(amm));
        console2.log("LP Token       :", address(amm.LP_TOKEN()));

        // 4. Lending pool ────────────────────────────────────────────────────
        require(
            collateralToken != address(0) && borrowToken    != address(0)
         && collateralFeed  != address(0) && borrowFeed     != address(0),
            "Deploy: set lending pool env vars"
        );
        lendingPool = new LendingPool(
            collateralToken,
            borrowToken,
            collateralFeed,
            borrowFeed,
            deployer
        );
        console2.log("LendingPool    :", address(lendingPool));

        // 5. Yield vault ─────────────────────────────────────────────────────
        yieldVault = new YieldVault(
            IERC20(borrowToken),
            "DeFi Yield Vault",
            "dyVAULT",
            deployer
        );
        console2.log("YieldVault     :", address(yieldVault));

        // 6. Factory ─────────────────────────────────────────────────────────
        factory = new ProtocolFactory(deployer);
        console2.log("Factory        :", address(factory));

        // 7. Treasury (UUPS proxy) ────────────────────────────────────────────
        TreasuryV1 implV1 = new TreasuryV1();
        console2.log("TreasuryV1 impl:", address(implV1));

        bytes memory initData = abi.encodeCall(TreasuryV1.initialize, (deployer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        treasury = TreasuryV1(payable(address(proxy)));
        console2.log("Treasury proxy :", address(treasury));

        // 8. Upgrade to V2 ───────────────────────────────────────────────────
        TreasuryV2 implV2 = new TreasuryV2();
        console2.log("TreasuryV2 impl:", address(implV2));

        bytes memory upgradeData = abi.encodeCall(
            TreasuryV2.initializeV2,
            (50, 10 ether) // 0.5% fee, 10 ETH timelock threshold
        );
        treasury.upgradeToAndCall(address(implV2), upgradeData);
        console2.log("Treasury upgraded to V2.");

        vm.stopBroadcast();

        _logSummary(deployer);
    }

    // ─── Summary ─────────────────────────────────────────────────────────────

    function _logSummary(address deployer) internal view {
        console2.log("\n========== DeFi Super-App Deployment Summary ==========");
        console2.log("Deployer       :", deployer);
        console2.log("Chain ID       :", block.chainid);
        console2.log("ProtocolToken  :", address(protocolToken));
        console2.log("AchievementNFT :", address(achievementNft));
        console2.log("AMM            :", address(amm));
        console2.log("LP Token       :", address(amm.LP_TOKEN()));
        console2.log("LendingPool    :", address(lendingPool));
        console2.log("YieldVault     :", address(yieldVault));
        console2.log("Factory        :", address(factory));
        console2.log("Treasury(proxy):", address(treasury));
        console2.log("=======================================================");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {AMM} from "../src/amm/AMM.sol";
import {LendingPool} from "../src/lending/LendingPool.sol";
import {YieldVault} from "../src/vault/YieldVault.sol";
import {ProtocolToken} from "../src/token/ProtocolToken.sol";
import {AchievementNFT} from "../src/nft/AchievementNFT.sol";
import {ProtocolFactory} from "../src/factory/ProtocolFactory.sol";
import {TreasuryV1} from "../src/treasury/TreasuryV1.sol";
import {TreasuryV2} from "../src/treasury/TreasuryV2.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Deploy
/// @notice Full reproducible deployment of the DeFi Super-App.
///         Deploys every contract, wires governance, and hands all admin
///         rights over to the Timelock so no EOA admin remains.
///
/// Usage:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url arbitrum_sepolia \
///     --broadcast --verify -vvvv
///
/// Required env vars:
///   PRIVATE_KEY            — deployer private key (0x-prefixed)
///   TOKEN_A                — first AMM token
///   TOKEN_B                — second AMM token
///   COLLATERAL_TOKEN       — lending collateral token
///   BORROW_TOKEN           — lending borrow token
///   COLLATERAL_PRICE_FEED  — Chainlink feed for collateral
///   BORROW_PRICE_FEED      — Chainlink feed for borrow asset
///
/// Optional:
///   INITIAL_GOV_SUPPLY     — initial PROTO tokens minted to deployer
///                            (default 10_000_000e18 — needed so proposalThreshold > 0)
contract Deploy is Script {
    // ─── Deployed addresses ──────────────────────────────────────────────────

    ProtocolToken public protocolToken;
    AchievementNFT public achievementNft;
    AMM public amm;
    LendingPool public lendingPool;
    YieldVault public yieldVault;
    ProtocolFactory public factory;
    TreasuryV1 public treasury; // proxy
    address public treasuryV1Impl;
    address public treasuryV2Impl;
    ProtocolTimelock public timelock;
    ProtocolGovernor public governor;

    // Same role constants used by the deployed contracts.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 internal constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    bytes32 internal constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address tokenA = vm.envAddress("TOKEN_A");
        address tokenB = vm.envAddress("TOKEN_B");
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        address borrowToken = vm.envAddress("BORROW_TOKEN");
        address collateralFeed = vm.envAddress("COLLATERAL_PRICE_FEED");
        address borrowFeed = vm.envAddress("BORROW_PRICE_FEED");
        uint256 initialSupply = vm.envOr("INITIAL_GOV_SUPPLY", uint256(10_000_000 ether));

        vm.startBroadcast(deployerKey);

        // 1. Protocol / governance token (ERC20Votes + Permit) ───────────────
        protocolToken = new ProtocolToken(deployer);

        // 2. Achievement NFT (soulbound badges) ──────────────────────────────
        achievementNft = new AchievementNFT(deployer);

        // 3. AMM (constant product) ─────────────────────────────────────────
        amm = new AMM(tokenA, tokenB);

        // 4. Lending pool ───────────────────────────────────────────────────
        lendingPool = new LendingPool(collateralToken, borrowToken, collateralFeed, borrowFeed, deployer);

        // 5. Yield vault (ERC-4626) ─────────────────────────────────────────
        yieldVault = new YieldVault(IERC20(borrowToken), "DeFi Yield Vault", "dyVAULT", deployer);

        // 6. Factory ────────────────────────────────────────────────────────
        factory = new ProtocolFactory(deployer);

        // 7. Treasury V1 behind UUPS proxy ──────────────────────────────────
        TreasuryV1 implV1 = new TreasuryV1();
        treasuryV1Impl = address(implV1);
        bytes memory initData = abi.encodeCall(TreasuryV1.initialize, (deployer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        treasury = TreasuryV1(payable(address(proxy)));

        // 8. Upgrade Treasury V1 → V2 ───────────────────────────────────────
        TreasuryV2 implV2 = new TreasuryV2();
        treasuryV2Impl = address(implV2);
        treasury.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(TreasuryV2.initializeV2, (50, 10 ether)) // 0.5% fee, 10 ETH timelock threshold
        );

        // 9. Bootstrap governance token supply ─────────────────────────────
        // Must mint BEFORE handover; proposalThreshold = 1% of supply, which
        // would be 0 (and proposals impossible to gate) if supply stayed at 0.
        ProtocolToken(protocolToken).mint(deployer, initialSupply);

        // 10. Timelock (2-day delay, deployer is temporary admin) ──────────
        address[] memory empty = new address[](0);
        timelock = new ProtocolTimelock(deployer, empty, empty);

        // 11. Governor (1d delay, 1w period, 4% quorum, 1% threshold) ──────
        governor = new ProtocolGovernor(IVotes(address(protocolToken)), TimelockController(payable(address(timelock))));

        // 12. Wire Governor into Timelock ──────────────────────────────────
        // Governor proposes; anyone can execute after delay (address(0) executor).
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));
        timelock.grantRole(EXECUTOR_ROLE, address(0));

        // 13. Hand admin/operator roles to the Timelock for every contract ─
        _handoverToTimelock(address(timelock), deployer);

        // 14. Renounce deployer's Timelock admin (no EOA backdoor) ─────────
        timelock.renounceRole(TIMELOCK_ADMIN_ROLE, deployer);

        vm.stopBroadcast();

        _logSummary(deployer);
        _writeDeploymentJson(deployer);
    }

    /// @dev Grants all admin/operator roles on every protocol contract to
    ///      `tl` (the Timelock), then renounces the deployer's roles.
    ///      AMM has no admin, so it's skipped.
    function _handoverToTimelock(address tl, address deployer) internal {
        // ProtocolToken — MINTER_ROLE so governance can mint via proposals.
        protocolToken.grantRole(DEFAULT_ADMIN_ROLE, tl);
        protocolToken.grantRole(MINTER_ROLE, tl);
        protocolToken.renounceRole(MINTER_ROLE, deployer);
        protocolToken.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // AchievementNFT
        achievementNft.grantRole(DEFAULT_ADMIN_ROLE, tl);
        achievementNft.grantRole(MINTER_ROLE, tl);
        achievementNft.renounceRole(MINTER_ROLE, deployer);
        achievementNft.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // LendingPool
        lendingPool.grantRole(DEFAULT_ADMIN_ROLE, tl);
        lendingPool.grantRole(ADMIN_ROLE, tl);
        lendingPool.renounceRole(ADMIN_ROLE, deployer);
        lendingPool.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // YieldVault
        yieldVault.grantRole(DEFAULT_ADMIN_ROLE, tl);
        yieldVault.grantRole(STRATEGIST_ROLE, tl);
        yieldVault.renounceRole(STRATEGIST_ROLE, deployer);
        yieldVault.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // ProtocolFactory
        factory.grantRole(DEFAULT_ADMIN_ROLE, tl);
        factory.grantRole(DEPLOYER_ROLE, tl);
        factory.renounceRole(DEPLOYER_ROLE, deployer);
        factory.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // Treasury (V2)
        treasury.grantRole(DEFAULT_ADMIN_ROLE, tl);
        treasury.grantRole(ADMIN_ROLE, tl);
        treasury.grantRole(UPGRADER_ROLE, tl);
        treasury.renounceRole(UPGRADER_ROLE, deployer);
        treasury.renounceRole(ADMIN_ROLE, deployer);
        treasury.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
    }

    function _logSummary(address deployer) internal view {
        console2.log("\n========== DeFi Super-App Deployment ==========");
        console2.log("Chain ID       :", block.chainid);
        console2.log("Deployer       :", deployer);
        console2.log("ProtocolToken  :", address(protocolToken));
        console2.log("AchievementNFT :", address(achievementNft));
        console2.log("AMM            :", address(amm));
        console2.log("LP Token       :", address(amm.LP_TOKEN()));
        console2.log("LendingPool    :", address(lendingPool));
        console2.log("YieldVault     :", address(yieldVault));
        console2.log("Factory        :", address(factory));
        console2.log("Treasury(proxy):", address(treasury));
        console2.log("TreasuryV1 impl:", treasuryV1Impl);
        console2.log("TreasuryV2 impl:", treasuryV2Impl);
        console2.log("Timelock       :", address(timelock));
        console2.log("Governor       :", address(governor));
        console2.log("===============================================");
    }

    /// @dev Writes a `deployments/<chainid>.json` file the frontend, subgraph,
    ///      and verification script can consume.
    function _writeDeploymentJson(address deployer) internal {
        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeAddress(obj, "protocolToken", address(protocolToken));
        vm.serializeAddress(obj, "achievementNft", address(achievementNft));
        vm.serializeAddress(obj, "amm", address(amm));
        vm.serializeAddress(obj, "lpToken", address(amm.LP_TOKEN()));
        vm.serializeAddress(obj, "lendingPool", address(lendingPool));
        vm.serializeAddress(obj, "yieldVault", address(yieldVault));
        vm.serializeAddress(obj, "factory", address(factory));
        vm.serializeAddress(obj, "treasury", address(treasury));
        vm.serializeAddress(obj, "treasuryV1Impl", treasuryV1Impl);
        vm.serializeAddress(obj, "treasuryV2Impl", treasuryV2Impl);
        vm.serializeAddress(obj, "timelock", address(timelock));
        string memory json = vm.serializeAddress(obj, "governor", address(governor));

        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Deployment JSON written to:", path);
    }
}

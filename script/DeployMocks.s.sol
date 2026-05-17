// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

/// @notice Mintable ERC-20 for testnet use.
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Returns a fixed price; used as a Chainlink feed stub on testnet.
contract MockAggregator {
    int256 private immutable _price;
    uint256 private immutable _updatedAt;

    constructor(int256 price_) {
        _price = price_;
        _updatedAt = block.timestamp;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}

/// @title DeployMocks
/// @notice Deploys mock tokens and Chainlink price feeds for testnet use.
///
/// Run this FIRST, then copy the printed addresses into your .env:
///
///   forge script script/DeployMocks.s.sol:DeployMocks \
///     --rpc-url arbitrum_sepolia \
///     --broadcast -vvvv
contract DeployMocks is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // ── Tokens ──────────────────────────────────────────────────────────
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH");
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");

        // Mint a generous supply to the deployer for testing.
        weth.mint(deployer, 1_000e18);
        usdc.mint(deployer, 2_000_000e18);

        // ── Price feeds ─────────────────────────────────────────────────────
        // ETH  = $2 000  →  200000000000  (8 decimals)
        // USDC = $1      →  100000000     (8 decimals)
        MockAggregator ethFeed = new MockAggregator(2_000e8);
        MockAggregator usdcFeed = new MockAggregator(1e8);

        vm.stopBroadcast();

        // ── Print addresses ─────────────────────────────────────────────────
        console2.log("========== Copy these into your .env ==========");
        console2.log("TOKEN_A=%s", address(weth));
        console2.log("TOKEN_B=%s", address(usdc));
        console2.log("COLLATERAL_TOKEN=%s", address(weth));
        console2.log("BORROW_TOKEN=%s", address(usdc));
        console2.log("COLLATERAL_PRICE_FEED=%s", address(ethFeed));
        console2.log("BORROW_PRICE_FEED=%s", address(usdcFeed));
        console2.log("===============================================");
    }
}

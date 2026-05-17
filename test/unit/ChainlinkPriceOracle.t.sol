// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainlinkPriceOracle} from "../../src/oracles/ChainlinkPriceOracle.sol";
import {MockV3Aggregator} from "../../src/oracles/MockV3Aggregator.sol";

/// @title ChainlinkPriceOracleTest
/// @notice Unit tests for the ChainlinkPriceOracle contract.
contract ChainlinkPriceOracleTest is Test {
    ChainlinkPriceOracle internal oracle;
    MockV3Aggregator internal ethFeed;
    MockV3Aggregator internal btcFeed;

    address internal admin = makeAddr("admin");
    address internal tokenETH = makeAddr("tokenETH");
    address internal tokenBTC = makeAddr("tokenBTC");
    address internal tokenXYZ = makeAddr("tokenXYZ");

    int256 internal constant ETH_PRICE = 2000e8; // $2000 with 8 decimals
    int256 internal constant BTC_PRICE = 40000e8; // $40000 with 8 decimals

    function setUp() public {
        // Warp to a realistic timestamp so staleness math doesn't underflow
        vm.warp(100_000);

        oracle = new ChainlinkPriceOracle(admin, 3600); // 1 hour staleness
        ethFeed = new MockV3Aggregator(8, ETH_PRICE);
        btcFeed = new MockV3Aggregator(8, BTC_PRICE);

        vm.startPrank(admin);
        oracle.setFeed(tokenETH, address(ethFeed));
        oracle.setFeed(tokenBTC, address(btcFeed));
        vm.stopPrank();
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    function test_constructor_setsMaxStaleness() public view {
        assertEq(oracle.maxStaleness(), 3600);
    }

    function test_constructor_grantsAdminRoles() public view {
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(oracle.hasRole(oracle.ORACLE_ADMIN_ROLE(), admin));
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(ChainlinkPriceOracle.ZeroAddress.selector);
        new ChainlinkPriceOracle(address(0), 3600);
    }

    function test_constructor_revertsOnZeroStaleness() public {
        vm.expectRevert(ChainlinkPriceOracle.ZeroStaleness.selector);
        new ChainlinkPriceOracle(admin, 0);
    }

    // ─── setFeed ─────────────────────────────────────────────────────────────

    function test_setFeed_success() public {
        MockV3Aggregator newFeed = new MockV3Aggregator(8, 1500e8);
        vm.prank(admin);
        oracle.setFeed(tokenXYZ, address(newFeed));
        assertEq(oracle.getPrice(tokenXYZ), uint256(1500e8));
    }

    function test_setFeed_revertsOnZeroToken() public {
        vm.prank(admin);
        vm.expectRevert(ChainlinkPriceOracle.ZeroAddress.selector);
        oracle.setFeed(address(0), address(ethFeed));
    }

    function test_setFeed_revertsOnZeroFeed() public {
        vm.prank(admin);
        vm.expectRevert(ChainlinkPriceOracle.ZeroAddress.selector);
        oracle.setFeed(tokenXYZ, address(0));
    }

    function test_setFeed_revertsWithoutRole() public {
        vm.prank(makeAddr("nobody"));
        vm.expectRevert();
        oracle.setFeed(tokenXYZ, address(ethFeed));
    }

    // ─── setMaxStaleness ─────────────────────────────────────────────────────

    function test_setMaxStaleness_success() public {
        vm.prank(admin);
        oracle.setMaxStaleness(7200);
        assertEq(oracle.maxStaleness(), 7200);
    }

    function test_setMaxStaleness_revertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(ChainlinkPriceOracle.ZeroStaleness.selector);
        oracle.setMaxStaleness(0);
    }

    // ─── getPrice ────────────────────────────────────────────────────────────

    function test_getPrice_returnsCorrectETHPrice() public view {
        uint256 price = oracle.getPrice(tokenETH);
        assertEq(price, uint256(ETH_PRICE));
    }

    function test_getPrice_returnsCorrectBTCPrice() public view {
        uint256 price = oracle.getPrice(tokenBTC);
        assertEq(price, uint256(BTC_PRICE));
    }

    function test_getPrice_revertsOnFeedNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.FeedNotSet.selector, tokenXYZ));
        oracle.getPrice(tokenXYZ);
    }

    function test_getPrice_revertsOnStalePrice() public {
        // Set updatedAt to 2 hours ago
        ethFeed.setUpdatedAt(block.timestamp - 7200);

        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkPriceOracle.StalePrice.selector, tokenETH, block.timestamp - 7200, block.timestamp
            )
        );
        oracle.getPrice(tokenETH);
    }

    function test_getPrice_revertsOnZeroPrice() public {
        ethFeed.updateAnswer(0);

        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.InvalidPrice.selector, tokenETH, int256(0)));
        oracle.getPrice(tokenETH);
    }

    function test_getPrice_revertsOnNegativePrice() public {
        ethFeed.updateAnswer(-100);

        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.InvalidPrice.selector, tokenETH, int256(-100)));
        oracle.getPrice(tokenETH);
    }

    function test_getPrice_worksAtExactStalenessThreshold() public {
        // Set updatedAt to exactly 1 hour ago — should still work (not stale)
        ethFeed.setUpdatedAt(block.timestamp - 3600);
        uint256 price = oracle.getPrice(tokenETH);
        assertEq(price, uint256(ETH_PRICE));
    }

    function test_getPrice_failsOneSecondPastStaleness() public {
        ethFeed.setUpdatedAt(block.timestamp - 3601);
        vm.expectRevert();
        oracle.getPrice(tokenETH);
    }

    // ─── getPriceWithDecimals ────────────────────────────────────────────────

    function test_getPriceWithDecimals_returnsCorrectValues() public view {
        (uint256 price, uint8 decimals) = oracle.getPriceWithDecimals(tokenETH);
        assertEq(price, uint256(ETH_PRICE));
        assertEq(decimals, 8);
    }

    // ─── getPriceNormalized ──────────────────────────────────────────────────

    function test_getPriceNormalized_8decimals() public view {
        uint256 price = oracle.getPriceNormalized(tokenETH);
        // $2000 with 8 dec → normalized to 18 dec = 2000 * 1e10
        assertEq(price, 2000e18);
    }

    function test_getPriceNormalized_18decimals() public {
        MockV3Aggregator feed18 = new MockV3Aggregator(18, 2000e18);
        vm.prank(admin);
        oracle.setFeed(tokenXYZ, address(feed18));

        uint256 price = oracle.getPriceNormalized(tokenXYZ);
        assertEq(price, 2000e18);
    }

    // ─── Price updates ───────────────────────────────────────────────────────

    function test_getPrice_reflectsUpdates() public {
        ethFeed.updateAnswer(3000e8);
        uint256 price = oracle.getPrice(tokenETH);
        assertEq(price, uint256(3000e8));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../src/vault/YieldVault.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title YieldVaultTest
/// @notice Unit tests for the ERC-4626 yield vault.
contract YieldVaultTest is Test {
    YieldVault  internal vault;
    MockERC20   internal asset;

    address internal admin     = makeAddr("admin");
    address internal alice     = makeAddr("alice");
    address internal bob       = makeAddr("bob");
    address internal strategist = makeAddr("strategist");

    uint256 internal constant INITIAL = 1_000e18;

    function setUp() public {
        asset = new MockERC20("Underlying", "UND");
        vault = new YieldVault(IERC20(address(asset)), "Yield Vault", "yVAULT", admin);

        // Grant strategist role — read role hash before prank so the view call doesn't consume it.
        bytes32 strategistRole = vault.STRATEGIST_ROLE();
        vm.prank(admin);
        vault.grantRole(strategistRole, strategist);

        // Fund users
        asset.mint(alice,      100_000e18);
        asset.mint(bob,        100_000e18);
        asset.mint(strategist, 10_000e18);
    }

    // ─── deposit ─────────────────────────────────────────────────────────────

    function test_deposit_firstDeposit_1to1Shares() public {
        vm.startPrank(alice);
        asset.approve(address(vault), INITIAL);
        uint256 shares = vault.deposit(INITIAL, alice);
        vm.stopPrank();

        // On the first deposit with no virtual offset, shares == assets.
        assertEq(shares, INITIAL);
        assertEq(vault.balanceOf(alice), INITIAL);
        assertEq(vault.totalAssets(), INITIAL);
    }

    function test_deposit_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    // ─── mint ────────────────────────────────────────────────────────────────

    function test_mint_exactShares() public {
        vm.startPrank(alice);
        asset.approve(address(vault), INITIAL);
        uint256 assetsUsed = vault.mint(INITIAL, alice);
        vm.stopPrank();

        assertEq(assetsUsed, INITIAL);
        assertEq(vault.balanceOf(alice), INITIAL);
    }

    // ─── withdraw ────────────────────────────────────────────────────────────

    function test_withdraw_exactAssets() public {
        _deposit(alice, INITIAL);

        uint256 assetBefore = asset.balanceOf(alice);
        vm.startPrank(alice);
        vault.withdraw(INITIAL, alice, alice);
        vm.stopPrank();

        assertEq(asset.balanceOf(alice), assetBefore + INITIAL);
        assertEq(vault.balanceOf(alice), 0);
    }

    // ─── redeem ──────────────────────────────────────────────────────────────

    function test_redeem_exactShares() public {
        _deposit(alice, INITIAL);

        uint256 shares = vault.balanceOf(alice);
        uint256 assetBefore = asset.balanceOf(alice);

        vm.startPrank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(received, INITIAL);
        assertEq(asset.balanceOf(alice), assetBefore + INITIAL);
    }

    // ─── yield accrual ───────────────────────────────────────────────────────

    function test_yieldHarvest_increasesSharePrice() public {
        // Alice deposits
        _deposit(alice, INITIAL);
        // Bob also deposits the same amount
        _deposit(bob,   INITIAL);

        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Strategist injects 200 tokens of yield
        vm.startPrank(strategist);
        asset.approve(address(vault), 200e18);
        vault.harvestYield(200e18);
        vm.stopPrank();

        // Total assets: 2000 + 200 = 2200, total shares: 2000
        // Each share redeems for 2200/2000 = 1.1 assets
        uint256 aliceRedeemable = vault.convertToAssets(aliceSharesBefore);
        // OZ ERC-4626 adds a virtual +1 to numerator/denominator for reentrancy safety,
        // so the result may be 1 wei below the naive expectation.
        assertApproxEqAbs(aliceRedeemable, 1_100e18, 1);

        assertEq(vault.totalYieldHarvested(), 200e18);
    }

    function test_yieldHarvest_onlyStrategist() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.harvestYield(100e18);
    }

    // ─── share price invariants ───────────────────────────────────────────────

    function test_sharePrice_doesNotDropOnDeposit() public {
        _deposit(alice, INITIAL);

        // Inject yield to push price above 1
        vm.startPrank(strategist);
        asset.approve(address(vault), 500e18);
        vault.harvestYield(500e18);
        vm.stopPrank();

        uint256 priceBefore = vault.convertToAssets(1e18); // price per 1 share

        // Bob deposits; this should NOT decrease share price.
        _deposit(bob, INITIAL);

        uint256 priceAfter = vault.convertToAssets(1e18);
        assertGe(priceAfter, priceBefore, "share price dropped on deposit");
    }

    function test_multipleUsersProportionalShares() public {
        _deposit(alice, 1_000e18);
        _deposit(bob,   3_000e18);

        // No yield injected — shares should be 1:3
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares   = vault.balanceOf(bob);
        assertApproxEqRel(bobShares, aliceShares * 3, 1e14, "share ratio mismatch");
    }

    // ─── ERC-4626 compliance helpers ──────────────────────────────────────────

    function test_previewDeposit_matchesDeposit() public {
        _deposit(alice, INITIAL); // set up pool first

        uint256 preview = vault.previewDeposit(500e18);
        vm.startPrank(bob);
        asset.approve(address(vault), 500e18);
        uint256 actual = vault.deposit(500e18, bob);
        vm.stopPrank();

        assertEq(actual, preview);
    }

    function test_previewRedeem_matchesRedeem() public {
        _deposit(alice, INITIAL);
        uint256 shares = vault.balanceOf(alice);

        uint256 preview = vault.previewRedeem(shares);
        vm.startPrank(alice);
        uint256 actual = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(actual, preview);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _deposit(address who, uint256 amount) internal {
        vm.startPrank(who);
        asset.approve(address(vault), amount);
        vault.deposit(amount, who);
        vm.stopPrank();
    }
}

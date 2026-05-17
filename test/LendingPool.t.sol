// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../src/lending/LendingPool.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {MockAggregator} from "./helpers/MockAggregator.sol";

/// @title LendingPoolTest
/// @notice Unit tests for the over-collateralised lending pool.
contract LendingPoolTest is Test {
    LendingPool internal pool;
    MockERC20 internal collateral; // "ETH-like", $2000/token
    MockERC20 internal borrow; // "USD-like", $1/token
    MockAggregator internal collFeed;
    MockAggregator internal borrowFeed;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie"); // liquidator

    // Prices in 8-decimal Chainlink format
    int256 internal constant COLL_PRICE = 2_000e8; // $2000 per collateral token
    int256 internal constant BORROW_PRICE = 1e8; // $1    per borrow token

    uint256 internal constant COLL_AMOUNT = 10e18; // 10 ETH-like tokens

    function setUp() public {
        collateral = new MockERC20("Collateral", "COLL");
        borrow = new MockERC20("Borrow", "BORR");
        collFeed = new MockAggregator(COLL_PRICE, 8);
        borrowFeed = new MockAggregator(BORROW_PRICE, 8);

        pool = new LendingPool(address(collateral), address(borrow), address(collFeed), address(borrowFeed), admin);

        // Seed initial liquidity so borrowers have tokens available
        borrow.mint(admin, 1_000_000e18);
        vm.startPrank(admin);
        borrow.approve(address(pool), 1_000_000e18);
        pool.provideLiquidity(1_000_000e18);
        vm.stopPrank();

        // Fund alice with collateral
        collateral.mint(alice, 100e18);
        // Fund charlie (liquidator) with borrow tokens
        borrow.mint(charlie, 500_000e18);
    }

    // ─── depositCollateral ────────────────────────────────────────────────────

    function test_depositCollateral() public {
        vm.startPrank(alice);
        collateral.approve(address(pool), COLL_AMOUNT);
        pool.depositCollateral(COLL_AMOUNT);
        vm.stopPrank();

        (uint256 coll,,,) = pool.positions(alice);
        assertEq(coll, COLL_AMOUNT);
        assertEq(pool.totalCollateral(), COLL_AMOUNT);
    }

    function test_depositCollateral_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.depositCollateral(0);
    }

    // ─── borrow ──────────────────────────────────────────────────────────────

    function test_borrow_upToLTV() public {
        _deposit(alice, COLL_AMOUNT);

        // maxBorrow: 10 ETH * $2000 * 75% / $1 = 15,000 borrow tokens
        uint256 expected = 15_000e18;
        assertEq(pool.maxBorrow(alice), expected);

        vm.startPrank(alice);
        pool.borrow(expected);
        vm.stopPrank();

        (, uint256 debt,,) = pool.positions(alice);
        assertEq(debt, expected);
        assertEq(borrow.balanceOf(alice), expected);
    }

    function test_borrow_revertsAboveLTV() public {
        _deposit(alice, COLL_AMOUNT);
        uint256 max = pool.maxBorrow(alice);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(LendingPool.BorrowExceedsLTV.selector, max + 1, max));
        pool.borrow(max + 1);
        vm.stopPrank();
    }

    // ─── repay ───────────────────────────────────────────────────────────────

    function test_repay_full() public {
        _deposit(alice, COLL_AMOUNT);
        uint256 borrowed = 10_000e18;

        vm.startPrank(alice);
        pool.borrow(borrowed);
        borrow.approve(address(pool), borrowed);
        pool.repay(borrowed);
        vm.stopPrank();

        (, uint256 debt,,) = pool.positions(alice);
        assertEq(debt, 0);
    }

    function test_repay_revertsWithNoDebt() public {
        _deposit(alice, COLL_AMOUNT);
        borrow.mint(alice, 1000e18);

        vm.startPrank(alice);
        borrow.approve(address(pool), 1000e18);
        vm.expectRevert(LendingPool.NoDebt.selector);
        pool.repay(1000e18);
        vm.stopPrank();
    }

    // ─── interest accrual ─────────────────────────────────────────────────────

    function test_interestAccrual_positive() public {
        _deposit(alice, COLL_AMOUNT);
        uint256 borrowed = 10_000e18;

        vm.startPrank(alice);
        pool.borrow(borrowed);
        vm.stopPrank();

        // Advance 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 pending = pool.pendingInterest(alice);
        // ~10% of 10_000e18 = 1_000e18 (within 1% tolerance for linear approx)
        assertApproxEqRel(pending, 1_000e18, 0.01e18);
    }

    // ─── withdrawCollateral ───────────────────────────────────────────────────

    function test_withdrawCollateral_afterRepay() public {
        _deposit(alice, COLL_AMOUNT);
        uint256 borrowed = 10_000e18;

        vm.startPrank(alice);
        pool.borrow(borrowed);
        borrow.approve(address(pool), borrowed);
        pool.repay(borrowed);
        pool.withdrawCollateral(COLL_AMOUNT);
        vm.stopPrank();

        (uint256 coll,,,) = pool.positions(alice);
        assertEq(coll, 0);
        assertEq(collateral.balanceOf(alice), 100e18); // original balance restored
    }

    function test_withdrawCollateral_revertsIfUnhealthy() public {
        _deposit(alice, COLL_AMOUNT);
        // Read maxBorrow before starting the prank so the view call doesn't consume it.
        uint256 maxToBorrow = pool.maxBorrow(alice);
        vm.prank(alice);
        pool.borrow(maxToBorrow);

        // Trying to withdraw any collateral should break the health factor.
        vm.prank(alice);
        vm.expectRevert();
        pool.withdrawCollateral(1e18);
    }

    // ─── liquidation ──────────────────────────────────────────────────────────

    function test_liquidate_unhealthyPosition() public {
        _deposit(alice, COLL_AMOUNT);
        uint256 borrowed = 14_000e18; // just under 75% LTV

        vm.prank(alice);
        pool.borrow(borrowed);

        // Drop collateral price so health factor < 1:
        // New value = 10 * 1300 * 0.80 / 14000 = 0.74 < 1 → liquidatable
        collFeed.setPrice(1_300e8);

        uint256 charlieCollBefore = collateral.balanceOf(charlie);

        vm.startPrank(charlie);
        borrow.approve(address(pool), 7_000e18);
        pool.liquidate(alice, 7_000e18);
        vm.stopPrank();

        // Charlie should have received collateral
        assertGt(collateral.balanceOf(charlie), charlieCollBefore, "liquidator got no collateral");
        // Alice's debt reduced
        (, uint256 debtAfter,,) = pool.positions(alice);
        assertLt(debtAfter, borrowed, "debt not reduced");
    }

    function test_liquidate_revertsWhenHealthy() public {
        _deposit(alice, COLL_AMOUNT);
        // Borrow only 1000 — very healthy
        vm.prank(alice);
        pool.borrow(1_000e18);

        vm.startPrank(charlie);
        borrow.approve(address(pool), 500e18);
        vm.expectRevert();
        pool.liquidate(alice, 500e18);
        vm.stopPrank();
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _deposit(address who, uint256 amount) internal {
        vm.startPrank(who);
        collateral.approve(address(pool), amount);
        pool.depositCollateral(amount);
        vm.stopPrank();
    }
}

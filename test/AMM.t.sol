// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AMM} from "../src/amm/AMM.sol";
import {LPToken} from "../src/amm/LPToken.sol";
import {MockERC20} from "./helpers/MockERC20.sol";

/// @title AMMTest
/// @notice Full-coverage unit tests for the constant-product AMM.
contract AMMTest is Test {
    AMM     internal amm;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    LPToken   internal lp;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");

    uint256 internal constant INITIAL_A = 1_000e18;
    uint256 internal constant INITIAL_B = 2_000e18;
    uint256 internal constant DEADLINE   = type(uint256).max;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        amm    = new AMM(address(tokenA), address(tokenB));
        lp     = amm.LP_TOKEN();

        // Fund actors
        tokenA.mint(alice, 100_000e18);
        tokenB.mint(alice, 200_000e18);
        tokenA.mint(bob,   50_000e18);
        tokenB.mint(bob,   100_000e18);
    }

    // ─── addLiquidity ─────────────────────────────────────────────────────────

    function test_addLiquidity_firstDeposit() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), INITIAL_A);
        tokenB.approve(address(amm), INITIAL_B);

        (uint256 a, uint256 b, uint256 liq) =
            amm.addLiquidity(INITIAL_A, INITIAL_B, 0, 0, alice, DEADLINE);

        assertEq(a, INITIAL_A, "amountA mismatch");
        assertEq(b, INITIAL_B, "amountB mismatch");
        // First depositor: sqrt(1000e18 * 2000e18) - 1000 = sqrt(2e42) - 1000
        uint256 expectedLiq = _sqrt(INITIAL_A * INITIAL_B) - 1_000;
        assertEq(liq, expectedLiq, "LP minted mismatch");
        assertEq(lp.balanceOf(alice), expectedLiq);
        assertEq(amm.reserveA(), INITIAL_A);
        assertEq(amm.reserveB(), INITIAL_B);
        vm.stopPrank();
    }

    function test_addLiquidity_secondDeposit_proportional() public {
        _seed(alice, INITIAL_A, INITIAL_B);

        // Bob adds half as much
        uint256 addA = 500e18;
        uint256 addB = 1_000e18;
        vm.startPrank(bob);
        tokenA.approve(address(amm), addA);
        tokenB.approve(address(amm), addB);
        (, , uint256 liq) = amm.addLiquidity(addA, addB, 0, 0, bob, DEADLINE);
        vm.stopPrank();

        // LP should be ~half of Alice's LP (minus the locked minimum).
        uint256 aliceLp = lp.balanceOf(alice);
        assertApproxEqRel(liq, aliceLp / 2, 1e15); // within 0.1%
    }

    function test_addLiquidity_revertsOnDeadlineExpired() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), INITIAL_A);
        tokenB.approve(address(amm), INITIAL_B);
        vm.expectRevert(abi.encodeWithSelector(AMM.DeadlineExpired.selector, block.timestamp - 1, block.timestamp));
        amm.addLiquidity(INITIAL_A, INITIAL_B, 0, 0, alice, block.timestamp - 1);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsOnSlippage() public {
        _seed(alice, INITIAL_A, INITIAL_B);

        // Bob tries to deposit with impossible minimum B
        vm.startPrank(bob);
        uint256 addA = 500e18;
        uint256 addB = 1_000e18;
        tokenA.approve(address(amm), addA);
        tokenB.approve(address(amm), addB);
        // Demand more B than will actually be used (optimal is 1000e18 exactly, demand 1001e18)
        vm.expectRevert();
        amm.addLiquidity(addA, addB, 0, 1_001e18, bob, DEADLINE);
        vm.stopPrank();
    }

    // ─── removeLiquidity ──────────────────────────────────────────────────────

    function test_removeLiquidity_full() public {
        _seed(alice, INITIAL_A, INITIAL_B);

        uint256 aliceLp = lp.balanceOf(alice);
        uint256 aliceABefore = tokenA.balanceOf(alice);
        uint256 aliceBBefore = tokenB.balanceOf(alice);

        vm.startPrank(alice);
        (uint256 retA, uint256 retB) = amm.removeLiquidity(aliceLp, 0, 0, alice, DEADLINE);
        vm.stopPrank();

        // Total supply is aliceLp + MINIMUM_LIQUIDITY.  Alice should get
        // aliceLp / (aliceLp + 1000) of each reserve back.
        assertGt(retA, 0, "zero tokenA returned");
        assertGt(retB, 0, "zero tokenB returned");
        assertEq(tokenA.balanceOf(alice), aliceABefore + retA);
        assertEq(tokenB.balanceOf(alice), aliceBBefore + retB);
        assertEq(lp.balanceOf(alice), 0, "LP not burned");
    }

    function test_removeLiquidity_revertsOnSlippage() public {
        _seed(alice, INITIAL_A, INITIAL_B);
        uint256 aliceLp = lp.balanceOf(alice);

        vm.startPrank(alice);
        // Demand more A than the pool can return for this LP amount
        vm.expectRevert();
        amm.removeLiquidity(aliceLp, type(uint256).max, 0, alice, DEADLINE);
        vm.stopPrank();
    }

    // ─── swap ────────────────────────────────────────────────────────────────

    function test_swap_AtoB() public {
        _seed(alice, INITIAL_A, INITIAL_B);

        uint256 swapIn = 100e18;
        uint256 expectedOut = amm.getAmountOut(address(tokenA), swapIn);
        assertGt(expectedOut, 0);

        uint256 bobBefore = tokenB.balanceOf(bob);
        vm.startPrank(bob);
        tokenA.approve(address(amm), swapIn);
        uint256 out = amm.swap(address(tokenA), swapIn, expectedOut, bob, DEADLINE);
        vm.stopPrank();

        assertEq(out, expectedOut, "output mismatch");
        assertEq(tokenB.balanceOf(bob), bobBefore + out, "bob B balance wrong");
    }

    function test_swap_BtoA() public {
        _seed(alice, INITIAL_A, INITIAL_B);

        uint256 swapIn = 200e18;
        uint256 expectedOut = amm.getAmountOut(address(tokenB), swapIn);

        vm.startPrank(bob);
        tokenB.approve(address(amm), swapIn);
        uint256 out = amm.swap(address(tokenB), swapIn, 0, bob, DEADLINE);
        vm.stopPrank();

        assertEq(out, expectedOut);
    }

    function test_swap_reversSlippageExceeded() public {
        _seed(alice, INITIAL_A, INITIAL_B);

        uint256 swapIn = 100e18;
        uint256 actualOut = amm.getAmountOut(address(tokenA), swapIn);

        vm.startPrank(bob);
        tokenA.approve(address(amm), swapIn);
        vm.expectRevert(abi.encodeWithSelector(AMM.SlippageExceeded.selector, actualOut, actualOut + 1));
        amm.swap(address(tokenA), swapIn, actualOut + 1, bob, DEADLINE);
        vm.stopPrank();
    }

    function test_swap_revertsOnInvalidToken() public {
        _seed(alice, INITIAL_A, INITIAL_B);
        address fakeToken = makeAddr("fakeToken");

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(AMM.InvalidToken.selector, fakeToken));
        amm.swap(fakeToken, 100e18, 0, bob, DEADLINE);
        vm.stopPrank();
    }

    function test_swap_feeAccrual_kIncreases() public {
        _seed(alice, INITIAL_A, INITIAL_B);

        uint256 kBefore = amm.reserveA() * amm.reserveB();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100e18);
        amm.swap(address(tokenA), 100e18, 0, bob, DEADLINE);
        vm.stopPrank();

        uint256 kAfter = amm.reserveA() * amm.reserveB();
        assertGt(kAfter, kBefore, "k must increase due to fee");
    }

    // ─── getSpotPrice ─────────────────────────────────────────────────────────

    function test_getSpotPrice() public {
        _seed(alice, INITIAL_A, INITIAL_B);
        (uint256 priceAinB, uint256 priceBinA) = amm.getSpotPrice();
        // reserveA=1000, reserveB=2000 → priceAinB = 2e18, priceBinA = 0.5e18
        assertEq(priceAinB, 2e18);
        assertEq(priceBinA, 5e17);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _seed(address who, uint256 a, uint256 b) internal {
        vm.startPrank(who);
        tokenA.approve(address(amm), a);
        tokenB.approve(address(amm), b);
        amm.addLiquidity(a, b, 0, 0, who, DEADLINE);
        vm.stopPrank();
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

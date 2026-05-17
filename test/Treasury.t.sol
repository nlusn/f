// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "../src/treasury/TreasuryV1.sol";
import {TreasuryV2} from "../src/treasury/TreasuryV2.sol";
import {MockERC20} from "./helpers/MockERC20.sol";

/// @title TreasuryTest
/// @notice Tests for TreasuryV1 + UUPS upgrade to TreasuryV2.
contract TreasuryTest is Test {
    TreasuryV1 internal treasury; // always points to proxy
    MockERC20 internal token;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");

    function setUp() public {
        // Deploy V1 implementation + proxy
        TreasuryV1 impl = new TreasuryV1();
        bytes memory init = abi.encodeCall(TreasuryV1.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        treasury = TreasuryV1(payable(address(proxy)));

        token = new MockERC20("Test", "TST");
        token.mint(alice, 10_000e18);
    }

    // ─── V1 ETH ──────────────────────────────────────────────────────────────

    function test_V1_depositEth() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        treasury.depositEth{value: 5 ether}();

        assertEq(treasury.ethBalance(), 5 ether);
        assertEq(treasury.ethDeposits(alice), 5 ether);
        assertEq(treasury.totalEthReceived(), 5 ether);
    }

    function test_V1_withdrawEth_byAdmin() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        treasury.depositEth{value: 1 ether}();

        uint256 adminBefore = admin.balance;
        vm.prank(admin);
        treasury.withdrawEth(payable(admin), 1 ether);

        assertEq(admin.balance, adminBefore + 1 ether);
        assertEq(treasury.ethBalance(), 0);
    }

    function test_V1_withdrawEth_revertsForNonAdmin() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        treasury.depositEth{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert();
        treasury.withdrawEth(payable(alice), 1 ether);
    }

    // ─── V1 ERC-20 ───────────────────────────────────────────────────────────

    function test_V1_depositAndWithdrawToken() public {
        vm.startPrank(alice);
        token.approve(address(treasury), 1_000e18);
        treasury.depositToken(address(token), 1_000e18);
        vm.stopPrank();

        assertEq(treasury.tokenBalance(address(token)), 1_000e18);

        vm.prank(admin);
        treasury.withdrawToken(address(token), admin, 500e18);

        assertEq(token.balanceOf(admin), 500e18);
        assertEq(treasury.tokenBalance(address(token)), 500e18);
    }

    // ─── UUPS Upgrade to V2 ──────────────────────────────────────────────────

    function _upgradeToV2(uint256 feeBps, uint256 threshold) internal returns (TreasuryV2 v2) {
        TreasuryV2 implV2 = new TreasuryV2();
        bytes memory data = abi.encodeCall(TreasuryV2.initializeV2, (feeBps, threshold));
        vm.prank(admin);
        treasury.upgradeToAndCall(address(implV2), data);
        v2 = TreasuryV2(payable(address(treasury)));
    }

    function test_upgrade_storagePreserved() public {
        // Deposit before upgrade
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        treasury.depositEth{value: 3 ether}();

        _upgradeToV2(50, 10 ether);

        // V1 storage must be intact
        assertEq(treasury.totalEthReceived(), 3 ether);
        assertEq(treasury.ethDeposits(alice), 3 ether);
    }

    function test_upgrade_V2_feeOnWithdrawal() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        treasury.depositEth{value: 5 ether}();

        TreasuryV2 v2 = _upgradeToV2(100, 100 ether); // 1% fee, very high threshold

        uint256 adminBefore = admin.balance;
        vm.prank(admin);
        v2.withdrawEth(payable(admin), 2 ether);

        // 1% fee on 2 ETH = 0.02 ETH; admin receives 1.98 ETH
        assertEq(admin.balance, adminBefore + 1.98 ether);
        assertEq(v2.accumulatedFees(), 0.02 ether);
    }

    function test_upgrade_V2_timelock() public {
        vm.deal(alice, 20 ether);
        vm.prank(alice);
        treasury.depositEth{value: 20 ether}();

        TreasuryV2 v2 = _upgradeToV2(0, 10 ether); // 10 ETH threshold

        // Large withdrawal must go through timelock
        vm.prank(admin);
        vm.expectRevert(); // BelowTimelockThreshold (amount is above threshold, so direct withdraw reverts)
        v2.withdrawEth(payable(admin), 10 ether);

        // Schedule it
        vm.prank(admin);
        bytes32 id = v2.scheduleWithdrawal(payable(admin), 10 ether);

        // Cannot execute before TIMELOCK_DELAY
        vm.prank(admin);
        vm.expectRevert();
        v2.executeWithdrawal(id, payable(admin), 10 ether);

        // Fast-forward 24 h
        vm.warp(block.timestamp + 24 hours + 1);

        uint256 adminBefore = admin.balance;
        vm.prank(admin);
        v2.executeWithdrawal(id, payable(admin), 10 ether);

        assertEq(admin.balance, adminBefore + 10 ether);
    }

    function test_upgrade_V2_nonUpgraderCannotUpgrade() public {
        TreasuryV2 implV2 = new TreasuryV2();
        vm.prank(alice);
        vm.expectRevert();
        treasury.upgradeToAndCall(address(implV2), "");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VulnerableAccessControl} from "../../src/security/VulnerableAccessControl.sol";
import {FixedAccessControl} from "../../src/security/FixedAccessControl.sol";

/// @title PhishingAttacker
/// @notice Contract that demonstrates tx.origin phishing attack.
contract PhishingAttacker {
    VulnerableAccessControl public victim;

    constructor(address _victim) {
        victim = VulnerableAccessControl(_victim);
    }

    /// @dev When the admin calls this function (e.g., tricked via phishing),
    ///      tx.origin == admin, so the check passes and funds go to the attacker.
    function executePhishing() external {
        victim.withdrawAll();
    }

    receive() external payable {}
}

/// @title AccessControlTest
/// @notice Tests demonstrating the access-control vulnerability and its fix.
contract AccessControlTest is Test {
    VulnerableAccessControl internal vulnerable;
    FixedAccessControl internal fixed_;

    address internal admin = makeAddr("admin");
    address internal attacker = makeAddr("attacker");
    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.startPrank(admin);
        vulnerable = new VulnerableAccessControl();
        vm.stopPrank();

        fixed_ = new FixedAccessControl(admin);
    }

    // ─── VulnerableAccessControl: Basic tests ────────────────────────────────

    function test_vulnerable_adminSetCorrectly() public view {
        assertEq(vulnerable.admin(), admin);
    }

    function test_vulnerable_deposit() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 5 ether}();
        assertEq(vulnerable.balances(alice), 5 ether);
        assertEq(vulnerable.getBalance(), 5 ether);
    }

    // ─── VulnerableAccessControl: Anyone can setAdmin ────────────────────────

    function test_vulnerable_anyoneCanSetAdmin() public {
        // Attacker takes over admin role — no access check!
        vm.prank(attacker);
        vulnerable.setAdmin(attacker);
        assertEq(vulnerable.admin(), attacker);
    }

    // ─── VulnerableAccessControl: tx.origin phishing ─────────────────────────

    function test_vulnerable_txOriginPhishing() public {
        // Setup: deposit funds
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 10 ether}();

        // Deploy phishing contract
        PhishingAttacker phisher = new PhishingAttacker(address(vulnerable));

        // Admin is tricked into calling the phisher contract
        // tx.origin == admin, so the check passes
        vm.prank(admin, admin); // sets both msg.sender and tx.origin
        phisher.executePhishing();

        // Phisher got all the funds!
        assertEq(address(phisher).balance, 10 ether);
        assertEq(vulnerable.getBalance(), 0);
    }

    // ─── FixedAccessControl: Basic tests ─────────────────────────────────────

    function test_fixed_adminHasRoles() public view {
        assertTrue(fixed_.hasRole(fixed_.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(fixed_.hasRole(fixed_.WITHDRAWER_ROLE(), admin));
    }

    function test_fixed_deposit() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();
        assertEq(fixed_.balances(alice), 5 ether);
    }

    function test_fixed_depositRevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(FixedAccessControl.ZeroAmount.selector);
        fixed_.deposit{value: 0}();
    }

    // ─── FixedAccessControl: Access properly enforced ────────────────────────

    function test_fixed_withdrawAllRevertsWithoutRole() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        vm.prank(attacker);
        vm.expectRevert();
        fixed_.withdrawAll(payable(attacker));
    }

    function test_fixed_withdrawAmountRevertsWithoutRole() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        vm.prank(attacker);
        vm.expectRevert();
        fixed_.withdrawAmount(payable(attacker), 1 ether);
    }

    function test_fixed_withdrawAllSuccess() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        uint256 adminBefore = admin.balance;
        vm.prank(admin);
        fixed_.withdrawAll(payable(admin));
        assertEq(admin.balance, adminBefore + 5 ether);
    }

    function test_fixed_withdrawAmountSuccess() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        uint256 adminBefore = admin.balance;
        vm.prank(admin);
        fixed_.withdrawAmount(payable(admin), 3 ether);
        assertEq(admin.balance, adminBefore + 3 ether);
    }

    function test_fixed_withdrawAmountRevertsOnInsufficient() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        fixed_.deposit{value: 1 ether}();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(FixedAccessControl.InsufficientBalance.selector, 1 ether, 5 ether));
        fixed_.withdrawAmount(payable(admin), 5 ether);
    }

    function test_fixed_withdrawAllRevertsOnEmpty() public {
        vm.prank(admin);
        vm.expectRevert(FixedAccessControl.ZeroAmount.selector);
        fixed_.withdrawAll(payable(admin));
    }

    function test_fixed_withdrawAmountRevertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(FixedAccessControl.ZeroAmount.selector);
        fixed_.withdrawAmount(payable(admin), 0);
    }

    // ─── FixedAccessControl: Role management ─────────────────────────────────

    function test_fixed_grantWithdrawerRole() public {
        address newWithdrawer = makeAddr("newWithdrawer");
        vm.startPrank(admin);
        fixed_.grantRole(fixed_.WITHDRAWER_ROLE(), newWithdrawer);
        vm.stopPrank();

        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        vm.prank(newWithdrawer);
        fixed_.withdrawAmount(payable(newWithdrawer), 2 ether);
        assertEq(newWithdrawer.balance, 2 ether);
    }

    function test_fixed_revokeWithdrawerRole() public {
        address tempWithdrawer = makeAddr("tempWithdrawer");
        vm.startPrank(admin);
        fixed_.grantRole(fixed_.WITHDRAWER_ROLE(), tempWithdrawer);
        fixed_.revokeRole(fixed_.WITHDRAWER_ROLE(), tempWithdrawer);
        vm.stopPrank();

        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        vm.prank(tempWithdrawer);
        vm.expectRevert();
        fixed_.withdrawAll(payable(tempWithdrawer));
    }

    // ─── FixedAccessControl: receive() ───────────────────────────────────────

    function test_fixed_receiveETH() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(fixed_).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(fixed_.getBalance(), 1 ether);
    }
}

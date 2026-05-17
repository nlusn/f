// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VulnerableReentrancy} from "../../src/security/VulnerableReentrancy.sol";
import {FixedReentrancy} from "../../src/security/FixedReentrancy.sol";

/// @title ReentrancyAttacker
/// @notice Attacker contract that exploits the reentrancy vulnerability.
contract ReentrancyAttacker {
    VulnerableReentrancy public victim;
    uint256 public attackCount;
    uint256 public maxAttacks;

    constructor(address _victim) {
        victim = VulnerableReentrancy(_victim);
        maxAttacks = 3;
    }

    function setMaxAttacks(uint256 _max) external {
        maxAttacks = _max;
    }

    function attack() external payable {
        victim.deposit{value: msg.value}();
        victim.withdraw();
    }

    receive() external payable {
        if (attackCount < maxAttacks && address(victim).balance >= msg.value) {
            attackCount++;
            victim.withdraw();
        }
    }
}

/// @title FixedReentrancyAttacker
/// @notice Attempts the same attack on the fixed version.
contract FixedReentrancyAttacker {
    FixedReentrancy public victim;
    uint256 public attackCount;

    constructor(address _victim) {
        victim = FixedReentrancy(_victim);
    }

    function attack() external payable {
        victim.deposit{value: msg.value}();
        victim.withdraw();
    }

    receive() external payable {
        if (address(victim).balance >= msg.value) {
            attackCount++;
            // This will revert due to ReentrancyGuard
            victim.withdraw();
        }
    }
}

/// @title ReentrancyTest
/// @notice Tests demonstrating the reentrancy vulnerability and its fix.
contract ReentrancyTest is Test {
    VulnerableReentrancy internal vulnerable;
    FixedReentrancy internal fixed_;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vulnerable = new VulnerableReentrancy();
        fixed_ = new FixedReentrancy();
    }

    // ─── VulnerableReentrancy: Basic tests ───────────────────────────────────

    function test_vulnerable_deposit() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 5 ether}();
        assertEq(vulnerable.balances(alice), 5 ether);
        assertEq(vulnerable.getBalance(), 5 ether);
    }

    function test_vulnerable_withdraw() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 5 ether}();

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        vulnerable.withdraw();
        assertEq(alice.balance, balBefore + 5 ether);
        assertEq(vulnerable.balances(alice), 0);
    }

    function test_vulnerable_depositRevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(VulnerableReentrancy.ZeroAmount.selector);
        vulnerable.deposit{value: 0}();
    }

    function test_vulnerable_withdrawRevertsOnNoBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VulnerableReentrancy.InsufficientBalance.selector, 0, 1));
        vulnerable.withdraw();
    }

    function test_vulnerable_withdrawAmountRevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(VulnerableReentrancy.ZeroAmount.selector);
        vulnerable.withdrawAmount(0);
    }

    function test_vulnerable_withdrawAmountRevertsOnInsufficient() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VulnerableReentrancy.InsufficientBalance.selector, 1 ether, 2 ether));
        vulnerable.withdrawAmount(2 ether);
    }

    // ─── VulnerableReentrancy: Attack succeeds ───────────────────────────────

    function test_vulnerable_reentrancyAttackSucceeds() public {
        // Victim deposits
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 10 ether}();

        // Attacker drains the contract
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(vulnerable));
        attacker.setMaxAttacks(10);
        vm.deal(address(attacker), 1 ether);
        attacker.attack{value: 1 ether}();

        // Attacker stole more than they deposited
        assertGt(address(attacker).balance, 1 ether);
        // Contract is drained
        assertEq(address(vulnerable).balance, 0);
    }

    // ─── FixedReentrancy: Basic tests ────────────────────────────────────────

    function test_fixed_deposit() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();
        assertEq(fixed_.balances(alice), 5 ether);
    }

    function test_fixed_withdraw() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        fixed_.withdraw();
        assertEq(alice.balance, balBefore + 5 ether);
        assertEq(fixed_.balances(alice), 0);
    }

    function test_fixed_depositRevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(FixedReentrancy.ZeroAmount.selector);
        fixed_.deposit{value: 0}();
    }

    function test_fixed_withdrawRevertsOnNoBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FixedReentrancy.InsufficientBalance.selector, 0, 1));
        fixed_.withdraw();
    }

    function test_fixed_withdrawAmountRevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(FixedReentrancy.ZeroAmount.selector);
        fixed_.withdrawAmount(0);
    }

    function test_fixed_withdrawAmountRevertsOnInsufficient() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        fixed_.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FixedReentrancy.InsufficientBalance.selector, 1 ether, 2 ether));
        fixed_.withdrawAmount(2 ether);
    }

    function test_fixed_withdrawAmountSuccess() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        fixed_.deposit{value: 5 ether}();

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        fixed_.withdrawAmount(2 ether);
        assertEq(alice.balance, balBefore + 2 ether);
        assertEq(fixed_.balances(alice), 3 ether);
    }

    // ─── FixedReentrancy: Attack fails ───────────────────────────────────────

    function test_fixed_reentrancyAttackFails() public {
        // Victim deposits
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        fixed_.deposit{value: 10 ether}();

        // Attacker tries to drain — should fail
        FixedReentrancyAttacker attacker = new FixedReentrancyAttacker(address(fixed_));
        vm.deal(address(attacker), 1 ether);
        // The attack reverts because the re-entrance is blocked
        vm.expectRevert();
        attacker.attack{value: 1 ether}();

        // Contract still has all funds
        assertEq(address(fixed_).balance, 10 ether);
    }
}

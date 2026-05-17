// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";

/// @title GovernanceTokenTest
/// @notice Unit tests for the GovernanceToken (ERC20Votes + ERC20Permit).
contract GovernanceTokenTest is Test {
    GovernanceToken internal token;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal minter = makeAddr("minter");

    function setUp() public {
        token = new GovernanceToken(admin);
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    function test_constructor_setsNameAndSymbol() public view {
        assertEq(token.name(), "Governance Token");
        assertEq(token.symbol(), "GOV");
    }

    function test_constructor_grantsAdminRoles() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
    }

    function test_constructor_zeroSupply() public view {
        assertEq(token.totalSupply(), 0);
    }

    // ─── Minting ─────────────────────────────────────────────────────────────

    function test_mint_success() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_mint_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit GovernanceToken.TokensMinted(alice, 500e18);
        vm.prank(admin);
        token.mint(alice, 500e18);
    }

    function test_mint_revertsOnZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(GovernanceToken.ZeroAmount.selector);
        token.mint(alice, 0);
    }

    function test_mint_revertsOnMaxSupplyExceeded() public {
        vm.startPrank(admin);
        token.mint(alice, token.MAX_SUPPLY());
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernanceToken.MaxSupplyExceeded.selector, token.MAX_SUPPLY(), 1, token.MAX_SUPPLY()
            )
        );
        token.mint(alice, 1);
        vm.stopPrank();
    }

    function test_mint_revertsWithoutMinterRole() public {
        vm.prank(bob);
        vm.expectRevert();
        token.mint(alice, 100e18);
    }

    function test_mint_newMinterRole() public {
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        vm.stopPrank();

        vm.prank(minter);
        token.mint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
    }

    // ─── Burning ─────────────────────────────────────────────────────────────

    function test_burn_success() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.burn(400e18);
        assertEq(token.balanceOf(alice), 600e18);
    }

    function test_burn_emitsEvent() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.expectEmit(true, false, false, true);
        emit GovernanceToken.TokensBurned(alice, 300e18);
        vm.prank(alice);
        token.burn(300e18);
    }

    function test_burn_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(GovernanceToken.ZeroAmount.selector);
        token.burn(0);
    }

    function test_burn_revertsOnInsufficientBalance() public {
        vm.prank(admin);
        token.mint(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GovernanceToken.InsufficientBalance.selector, 100e18, 200e18));
        token.burn(200e18);
    }

    // ─── ERC20Votes delegation ───────────────────────────────────────────────

    function test_delegation_selfDelegate() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1000e18);
    }

    function test_delegation_delegateToOther() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(bob), 1000e18);
        assertEq(token.getVotes(alice), 0);
    }

    function test_delegation_votesTrackAfterTransfer() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1000e18);

        vm.prank(alice);
        token.transfer(bob, 300e18);

        // Alice's votes decrease, bob hasn't delegated so has 0 votes
        assertEq(token.getVotes(alice), 700e18);
        assertEq(token.getVotes(bob), 0);
    }

    function test_delegation_historicalVotes() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.delegate(alice);

        uint256 blockBefore = block.number;
        vm.roll(block.number + 1);

        // Past votes should be available
        assertEq(token.getPastVotes(alice, blockBefore), 1000e18);
    }

    // ─── ERC20Permit ─────────────────────────────────────────────────────────

    function test_permit_nonces() public view {
        assertEq(token.nonces(alice), 0);
    }

    function test_permit_domainSeparator() public view {
        // Just verify it doesn't revert and returns non-zero
        bytes32 ds = token.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0));
    }

    // ─── MAX_SUPPLY ──────────────────────────────────────────────────────────

    function test_maxSupply_constant() public view {
        assertEq(token.MAX_SUPPLY(), 100_000_000 * 1e18);
    }

    function test_mint_exactMaxSupply() public {
        vm.startPrank(admin);
        token.mint(alice, token.MAX_SUPPLY());
        vm.stopPrank();
        assertEq(token.totalSupply(), token.MAX_SUPPLY());
    }

    // ─── Transfer ────────────────────────────────────────────────────────────

    function test_transfer_success() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.transfer(bob, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.balanceOf(bob), 500e18);
    }

    function test_approve_and_transferFrom() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.approve(bob, 300e18);

        vm.prank(bob);
        token.transferFrom(alice, bob, 300e18);
        assertEq(token.balanceOf(bob), 300e18);
    }
}

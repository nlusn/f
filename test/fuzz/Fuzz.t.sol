// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {ChainlinkPriceOracle} from "../../src/oracles/ChainlinkPriceOracle.sol";
import {MockV3Aggregator} from "../../src/oracles/MockV3Aggregator.sol";
import {FixedReentrancy} from "../../src/security/FixedReentrancy.sol";
import {FixedAccessControl} from "../../src/security/FixedAccessControl.sol";

/// @title FuzzTests
/// @notice Property-based fuzz tests for governance, oracle, and security contracts.
contract FuzzTests is Test {
    GovernanceToken internal token;
    ChainlinkPriceOracle internal oracle;
    FixedReentrancy internal reentrant;
    FixedAccessControl internal accessCtrl;

    address internal admin = makeAddr("admin");
    address internal tokenAddr = makeAddr("token");
    MockV3Aggregator internal feed;

    function setUp() public {
        vm.warp(100_000); // Prevent timestamp underflows
        token = new GovernanceToken(admin);
        oracle = new ChainlinkPriceOracle(admin, 3600);
        feed = new MockV3Aggregator(8, 2000e8);
        reentrant = new FixedReentrancy();
        accessCtrl = new FixedAccessControl(admin);

        vm.prank(admin);
        oracle.setFeed(tokenAddr, address(feed));
    }

    // ─── GovernanceToken Fuzz Tests ──────────────────────────────────────────

    /// @notice Minting any valid amount <= remaining supply should succeed.
    function testFuzz_mint_validAmount(uint256 amount) public {
        amount = bound(amount, 1, token.MAX_SUPPLY());
        vm.prank(admin);
        token.mint(admin, amount);
        assertEq(token.totalSupply(), amount);
        assertEq(token.balanceOf(admin), amount);
    }

    /// @notice Burn should always reduce balance by exactly the burned amount.
    function testFuzz_burn_reducesBalance(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, token.MAX_SUPPLY());
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.prank(admin);
        token.mint(admin, mintAmount);

        vm.prank(admin);
        token.burn(burnAmount);

        assertEq(token.balanceOf(admin), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    /// @notice Delegated votes should always equal the delegator's balance.
    function testFuzz_delegation_matchesBalance(uint256 amount) public {
        amount = bound(amount, 1, token.MAX_SUPPLY());
        address delegator = makeAddr("delegator");

        vm.prank(admin);
        token.mint(delegator, amount);

        vm.prank(delegator);
        token.delegate(delegator);

        assertEq(token.getVotes(delegator), amount);
    }

    /// @notice Transfer should maintain total supply invariant.
    function testFuzz_transfer_preservesTotalSupply(uint256 mintAmount, uint256 transferAmount) public {
        mintAmount = bound(mintAmount, 1, token.MAX_SUPPLY());
        transferAmount = bound(transferAmount, 0, mintAmount);
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");

        vm.prank(admin);
        token.mint(sender, mintAmount);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(sender);
        token.transfer(receiver, transferAmount);

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(sender) + token.balanceOf(receiver), mintAmount);
    }

    // ─── ChainlinkPriceOracle Fuzz Tests ─────────────────────────────────────

    /// @notice Any positive price should be returned correctly.
    function testFuzz_oracle_returnsPositivePrice(int256 price) public {
        uint256 absPrice = price < 0 ? (price == type(int256).min ? 1 : uint256(-price)) : uint256(price);
        price = int256(bound(absPrice, 1, type(uint128).max));
        feed.updateAnswer(price);

        uint256 result = oracle.getPrice(tokenAddr);
        assertEq(result, uint256(price));
    }

    /// @notice Negative or zero prices should always revert.
    function testFuzz_oracle_revertsOnInvalidPrice(int256 price) public {
        uint256 absPrice = price < 0 ? (price == type(int256).min ? 1 : uint256(-price)) : uint256(price);
        price = int256(bound(absPrice, 0, type(uint128).max));
        price = -price; // Make negative
        if (price == 0) price = 0; // include zero

        feed.updateAnswer(price);
        vm.expectRevert();
        oracle.getPrice(tokenAddr);
    }

    /// @notice Staleness beyond threshold should revert.
    function testFuzz_oracle_stalePriceReverts(uint256 staleDelta) public {
        staleDelta = bound(staleDelta, 3601, 100_000);
        feed.setUpdatedAt(block.timestamp - staleDelta);

        vm.expectRevert();
        oracle.getPrice(tokenAddr);
    }

    /// @notice Price within staleness window should succeed.
    function testFuzz_oracle_freshPriceSucceeds(uint256 freshDelta) public {
        freshDelta = bound(freshDelta, 0, 3600);
        feed.setUpdatedAt(block.timestamp - freshDelta);

        uint256 result = oracle.getPrice(tokenAddr);
        assertEq(result, uint256(2000e8));
    }

    // ─── FixedReentrancy Fuzz Tests ──────────────────────────────────────────

    /// @notice Deposit and withdraw should always return exact amount.
    function testFuzz_fixed_depositWithdraw(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);
        address user = makeAddr("user");
        vm.deal(user, amount);

        vm.prank(user);
        reentrant.deposit{value: amount}();
        assertEq(reentrant.balances(user), amount);

        uint256 balBefore = user.balance;
        vm.prank(user);
        reentrant.withdraw();

        assertEq(user.balance, balBefore + amount);
        assertEq(reentrant.balances(user), 0);
    }

    /// @notice Partial withdrawal should always leave correct remainder.
    function testFuzz_fixed_partialWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, 100 ether);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        address user = makeAddr("user");
        vm.deal(user, depositAmount);

        vm.prank(user);
        reentrant.deposit{value: depositAmount}();

        vm.prank(user);
        reentrant.withdrawAmount(withdrawAmount);

        assertEq(reentrant.balances(user), depositAmount - withdrawAmount);
    }
}

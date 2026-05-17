// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {FixedReentrancy} from "../../src/security/FixedReentrancy.sol";

/// @title TokenHandler
/// @notice Handler contract for invariant testing of GovernanceToken.
contract TokenHandler is Test {
    GovernanceToken public token;
    address public admin;

    uint256 public ghost_totalMinted;
    uint256 public ghost_totalBurned;

    constructor(GovernanceToken _token, address _admin) {
        token = _token;
        admin = _admin;
    }

    function mint(address to, uint256 amount) external {
        amount = bound(amount, 1, 1_000_000e18);
        if (to == address(0)) to = address(1);
        if (token.totalSupply() + amount > token.MAX_SUPPLY()) return;

        vm.prank(admin);
        token.mint(to, amount);
        ghost_totalMinted += amount;
    }

    function burn(uint256 amount) external {
        uint256 bal = token.balanceOf(admin);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);

        vm.prank(admin);
        token.burn(amount);
        ghost_totalBurned += amount;
    }

    function transfer(address from, address to, uint256 amount) external {
        if (from == address(0)) from = address(1);
        if (to == address(0)) to = address(1);
        uint256 bal = token.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);

        vm.prank(from);
        token.transfer(to, amount);
    }
}

/// @title VaultHandler
/// @notice Handler contract for invariant testing of FixedReentrancy vault.
contract VaultHandler is Test {
    FixedReentrancy public vault;
    address[] public actors;

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    constructor(FixedReentrancy _vault) {
        vault = _vault;
        for (uint256 i = 0; i < 5; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    function deposit(uint256 actorIdx, uint256 amount) external {
        actorIdx = actorIdx % actors.length;
        address actor = actors[actorIdx];
        amount = bound(amount, 1, 10 ether);
        if (actor.balance < amount) return;

        vm.prank(actor);
        vault.deposit{value: amount}();
        ghost_totalDeposited += amount;
    }

    function withdraw(uint256 actorIdx) external {
        actorIdx = actorIdx % actors.length;
        address actor = actors[actorIdx];
        uint256 bal = vault.balances(actor);
        if (bal == 0) return;

        vm.prank(actor);
        vault.withdraw();
        ghost_totalWithdrawn += bal;
    }

    function withdrawAmount(uint256 actorIdx, uint256 amount) external {
        actorIdx = actorIdx % actors.length;
        address actor = actors[actorIdx];
        uint256 bal = vault.balances(actor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);

        vm.prank(actor);
        vault.withdrawAmount(amount);
        ghost_totalWithdrawn += amount;
    }
}

/// @title InvariantTests
/// @notice Invariant tests that must hold across all sequences of operations.
contract InvariantTests is StdInvariant, Test {
    GovernanceToken internal token;
    FixedReentrancy internal vault;
    TokenHandler internal tokenHandler;
    VaultHandler internal vaultHandler;

    address internal admin = makeAddr("admin");

    function setUp() public {
        // Token setup
        token = new GovernanceToken(admin);
        tokenHandler = new TokenHandler(token, admin);

        // Vault setup
        vault = new FixedReentrancy();
        vaultHandler = new VaultHandler(vault);

        // Only target handlers
        targetContract(address(tokenHandler));
        targetContract(address(vaultHandler));
    }

    // ─── Token Invariants ────────────────────────────────────────────────────

    /// @notice totalSupply == totalMinted - totalBurned
    function invariant_token_supplyConsistency() public view {
        assertEq(token.totalSupply(), tokenHandler.ghost_totalMinted() - tokenHandler.ghost_totalBurned());
    }

    /// @notice totalSupply never exceeds MAX_SUPPLY
    function invariant_token_supplyNeverExceedsCap() public view {
        assertLe(token.totalSupply(), token.MAX_SUPPLY());
    }

    // ─── Vault Invariants ────────────────────────────────────────────────────

    /// @notice Vault's ETH balance should always equal total deposited - total withdrawn.
    function invariant_vault_balanceConsistency() public view {
        assertEq(address(vault).balance, vaultHandler.ghost_totalDeposited() - vaultHandler.ghost_totalWithdrawn());
    }

    /// @notice Vault's ETH balance should never be negative (it can't, but testing solvency).
    function invariant_vault_solvent() public view {
        assertGe(address(vault).balance, 0);
    }

    /// @notice Sum of user balances should equal vault ETH balance.
    function invariant_vault_userBalancesMatchContractBalance() public view {
        uint256 totalUserBalances = 0;
        for (uint256 i = 0; i < 5; i++) {
            address actor = vaultHandler.actors(i);
            totalUserBalances += vault.balances(actor);
        }
        assertEq(totalUserBalances, address(vault).balance);
    }
}

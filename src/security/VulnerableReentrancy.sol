// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VulnerableReentrancy
/// @notice ⚠️  INTENTIONALLY VULNERABLE — DO NOT DEPLOY!
///
/// @dev    Demonstrates a classic reentrancy vulnerability:
///         1. User deposits ETH.
///         2. User calls `withdraw()`.
///         3. The contract sends ETH via `.call{value:}("")` BEFORE updating state.
///         4. An attacker contract can re-enter `withdraw()` during the callback.
///
///         This contract is used as a case study alongside FixedReentrancy.sol.
contract VulnerableReentrancy {
    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    error ZeroAmount();
    error InsufficientBalance(uint256 have, uint256 want);
    error TransferFailed();

    /// @notice Deposit ETH into the vault.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw all deposited ETH.
    /// @dev    BUG: state update happens AFTER external call, enabling reentrancy!
    function withdraw() external {
        uint256 bal = balances[msg.sender];
        if (bal == 0) revert InsufficientBalance(0, 1);

        // ❌ VULNERABLE: external call BEFORE state update
        (bool ok,) = msg.sender.call{value: bal}("");
        if (!ok) revert TransferFailed();

        // State update happens after external call — too late!
        balances[msg.sender] = 0;

        emit Withdrawn(msg.sender, bal);
    }

    /// @notice Withdraw a specific amount.
    /// @dev    BUG: same reentrancy issue as withdraw().
    function withdrawAmount(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount) revert InsufficientBalance(balances[msg.sender], amount);

        // ❌ VULNERABLE: external call BEFORE state update
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        balances[msg.sender] -= amount;

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the contract's ETH balance.
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

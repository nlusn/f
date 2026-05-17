// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title FixedReentrancy
/// @notice ✅  SECURE version — fixes the reentrancy vulnerability from VulnerableReentrancy.sol.
///
/// @dev    Two mitigations applied:
///         1. **Checks-Effects-Interactions (CEI) pattern**: state is updated BEFORE the
///            external ETH transfer.
///         2. **OpenZeppelin ReentrancyGuard**: `nonReentrant` modifier prevents re-entrance
///            even if CEI is accidentally broken in a future refactor.
///
///         This contract is used as a case study alongside VulnerableReentrancy.sol.
contract FixedReentrancy is ReentrancyGuard {
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
    /// @dev    FIX: nonReentrant + state update BEFORE external call.
    function withdraw() external nonReentrant {
        uint256 bal = balances[msg.sender];
        if (bal == 0) revert InsufficientBalance(0, 1);

        // ✅ Effects: update state first
        balances[msg.sender] = 0;

        // ✅ Interactions: external call last
        (bool ok,) = msg.sender.call{value: bal}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(msg.sender, bal);
    }

    /// @notice Withdraw a specific amount.
    /// @dev    FIX: nonReentrant + state update BEFORE external call.
    function withdrawAmount(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount) revert InsufficientBalance(balances[msg.sender], amount);

        // ✅ Effects: update state first
        balances[msg.sender] -= amount;

        // ✅ Interactions: external call last
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the contract's ETH balance.
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

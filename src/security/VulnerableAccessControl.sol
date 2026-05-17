// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title VulnerableAccessControl
/// @notice ⚠️  INTENTIONALLY VULNERABLE — DO NOT DEPLOY!
///
/// @dev    Demonstrates common access-control vulnerabilities:
///         1. `setAdmin` has no access check — anyone can take ownership.
///         2. `withdrawAll` uses `tx.origin` instead of `msg.sender` — susceptible to
///            phishing attacks through intermediate contracts.
///         3. No role-based access — single owner with no separation of duties.
///
///         This contract is used as a case study alongside FixedAccessControl.sol.
contract VulnerableAccessControl {
    using SafeERC20 for IERC20;

    address public admin;
    mapping(address => uint256) public balances;

    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    error TransferFailed();

    constructor() {
        admin = msg.sender;
    }

    /// @notice Deposit ETH.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice ❌ BUG: No access control — anyone can call this and become admin!
    function setAdmin(address newAdmin) external {
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }

    /// @notice ❌ BUG: Uses tx.origin instead of msg.sender — phishing vulnerability!
    function withdrawAll() external {
        // solhint-disable-next-line avoid-tx-origin
        require(tx.origin == admin, "Not admin");
        uint256 bal = address(this).balance;
        (bool ok,) = msg.sender.call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, bal);
    }

    /// @notice Withdraw a specific amount. Still uses tx.origin.
    function withdrawAmount(uint256 amount) external {
        // solhint-disable-next-line avoid-tx-origin
        require(tx.origin == admin, "Not admin");
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the contract's ETH balance.
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

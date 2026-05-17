// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title FixedAccessControl
/// @notice ✅  SECURE version — fixes the access-control vulnerabilities from VulnerableAccessControl.sol.
///
/// @dev    Fixes applied:
///         1. **OpenZeppelin AccessControl**: proper role-based access with DEFAULT_ADMIN_ROLE
///            and WITHDRAWER_ROLE for separation of duties.
///         2. **No tx.origin**: all access checks use msg.sender via role modifiers.
///         3. **ReentrancyGuard**: prevents re-entrance on withdrawal functions.
///         4. **onlyRole modifiers**: every privileged function has explicit access checks.
///
///         This contract is used as a case study alongside VulnerableAccessControl.sol.
contract FixedAccessControl is AccessControl, ReentrancyGuard {
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    error ZeroAmount();
    error TransferFailed();
    error InsufficientBalance(uint256 available, uint256 requested);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(WITHDRAWER_ROLE, admin);
    }

    /// @notice Deposit ETH.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice ✅ FIX: Only WITHDRAWER_ROLE can withdraw. Uses msg.sender (not tx.origin).
    function withdrawAll(address payable recipient) external onlyRole(WITHDRAWER_ROLE) nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert ZeroAmount();

        (bool ok,) = recipient.call{value: bal}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(recipient, bal);
    }

    /// @notice ✅ FIX: Only WITHDRAWER_ROLE, with amount check.
    function withdrawAmount(address payable recipient, uint256 amount) external onlyRole(WITHDRAWER_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 available = address(this).balance;
        if (available < amount) revert InsufficientBalance(available, amount);

        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(recipient, amount);
    }

    /// @notice Returns the contract's ETH balance.
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Accept ETH transfers.
    receive() external payable {}
}

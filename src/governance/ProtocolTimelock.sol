// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title ProtocolTimelock
/// @notice TimelockController wrapper for the protocol governance system.
///
/// @dev    The timelock enforces a 2-day delay between a proposal being queued
///         and its execution.  This gives token holders time to react to passed
///         proposals (e.g., exit the protocol if they disagree).
///
///         Roles:
///         - PROPOSER_ROLE: Governor contract (proposes operations)
///         - EXECUTOR_ROLE: open (address(0) — anyone can execute after delay)
///         - DEFAULT_ADMIN_ROLE: admin (can configure roles)
contract ProtocolTimelock is TimelockController {
    /// @dev 2-day minimum delay (in seconds).
    uint256 public constant MIN_DELAY = 2 days;

    /// @param admin     Initial admin of the timelock
    /// @param proposers Addresses allowed to propose (typically just the Governor)
    /// @param executors Addresses allowed to execute (typically address(0) = open)
    constructor(address admin, address[] memory proposers, address[] memory executors)
        TimelockController(MIN_DELAY, proposers, executors, admin)
    {}
}

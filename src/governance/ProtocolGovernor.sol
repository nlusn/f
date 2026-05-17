// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title ProtocolGovernor
/// @notice OpenZeppelin Governor-based on-chain governance for the DeFi protocol.
///
/// @dev    Configuration:
///         - Voting delay:  1 day   (7200 blocks at 12 s/block)
///         - Voting period: 1 week  (50400 blocks at 12 s/block)
///         - Proposal threshold: 1% of total supply
///         - Quorum: 4% of total supply
///         - Timelock: all successful proposals are queued through TimelockController
///           with a 2-day delay before execution.
///
///         Full lifecycle: propose → vote → queue → execute
contract ProtocolGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param _token    The ERC20Votes governance token
    /// @param _timelock The TimelockController that queues/executes proposals
    constructor(IVotes _token, TimelockController _timelock)
        Governor("Protocol Governor")
        GovernorSettings(
            7200, // votingDelay:  1 day   (7200 blocks * 12s = 86400s)
            50400, // votingPeriod: 1 week  (50400 blocks * 12s = 604800s)
            0 // proposalThreshold: set to 0 here, overridden below
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4% quorum
        GovernorTimelockControl(_timelock)
    {}

    // ─── Overrides ───────────────────────────────────────────────────────────

    /// @notice Proposal threshold: 1% of current token supply.
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return token().getPastTotalSupply(clock() - 1) / 100;
    }

    // ─── Required resolution overrides ───────────────────────────────────────

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title GovernorTest
/// @notice Unit tests for the ProtocolGovernor + TimelockController lifecycle.
contract GovernorTest is Test {
    GovernanceToken internal token;
    ProtocolTimelock internal timelock;
    ProtocolGovernor internal governor;

    address internal admin = makeAddr("admin");
    address internal voter = makeAddr("voter");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant INITIAL_MINT = 10_000_000e18; // 10M tokens

    function setUp() public {
        token = new GovernanceToken(admin);

        // Set up timelock: governor will be proposer; anyone can execute
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute

        timelock = new ProtocolTimelock(admin, proposers, executors);
        governor = new ProtocolGovernor(IVotes(address(token)), TimelockController(payable(address(timelock))));

        // Grant governor the PROPOSER_ROLE on timelock
        vm.startPrank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        vm.stopPrank();

        // Mint tokens and delegate to voter
        vm.prank(admin);
        token.mint(voter, INITIAL_MINT);

        vm.prank(voter);
        token.delegate(voter);

        // Advance block so votes are checkpointed
        vm.roll(block.number + 1);
    }

    // ─── Governor configuration ──────────────────────────────────────────────

    function test_governor_name() public view {
        assertEq(governor.name(), "Protocol Governor");
    }

    function test_governor_votingDelay() public view {
        assertEq(governor.votingDelay(), 7200);
    }

    function test_governor_votingPeriod() public view {
        assertEq(governor.votingPeriod(), 50400);
    }

    function test_governor_quorum() public view {
        // 4% of 10M = 400K
        uint256 q = governor.quorum(block.number - 1);
        assertEq(q, INITIAL_MINT * 4 / 100);
    }

    function test_governor_proposalThreshold() public view {
        // 1% of total supply
        uint256 pt = governor.proposalThreshold();
        assertEq(pt, INITIAL_MINT / 100);
    }

    // ─── Timelock configuration ──────────────────────────────────────────────

    function test_timelock_minDelay() public view {
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function test_timelock_governorIsProposer() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
    }

    // ─── Full governance lifecycle ───────────────────────────────────────────

    function test_governance_fullLifecycle() public {
        // Fund the timelock so it can send ETH
        vm.deal(address(timelock), 1 ether);

        // Build a proposal: send 0.5 ETH to recipient
        address[] memory targets = new address[](1);
        targets[0] = recipient;
        uint256[] memory values = new uint256[](1);
        values[0] = 0.5 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "Send 0.5 ETH to recipient";

        // 1. Propose
        vm.prank(voter);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertGt(proposalId, 0);

        // State should be Pending
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // 2. Advance past voting delay
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + (governor.votingDelay() + 1) * 12);

        // State should be Active
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // 3. Vote
        vm.prank(voter);
        governor.castVote(proposalId, 1); // 1 = For

        // 4. Advance past voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + (governor.votingPeriod() + 1) * 12);

        // State should be Succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // 5. Queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // State should be Queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // 6. Advance past timelock delay
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // 7. Execute
        uint256 balBefore = recipient.balance;
        governor.execute(targets, values, calldatas, descHash);

        // State should be Executed
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        // Recipient should have received ETH
        assertEq(recipient.balance, balBefore + 0.5 ether);
    }

    // ─── Proposal rejection ─────────────────────────────────────────────────

    function test_governance_proposalDefeated() public {
        // Build a simple proposal
        address[] memory targets = new address[](1);
        targets[0] = address(0x1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(voter);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Bad proposal");

        // Advance past voting delay
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + (governor.votingDelay() + 1) * 12);

        // Vote against
        vm.prank(voter);
        governor.castVote(proposalId, 0); // 0 = Against

        // Advance past voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + (governor.votingPeriod() + 1) * 12);

        // State should be Defeated
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ─── Insufficient votes for proposal ─────────────────────────────────────

    function test_governance_insufficientVotesToPropose() public {
        address nobody = makeAddr("nobody");
        vm.prank(admin);
        token.mint(nobody, 1e18); // Way below 1% threshold

        vm.prank(nobody);
        token.delegate(nobody);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(0x1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(nobody);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    // ─── Voting power tracking ───────────────────────────────────────────────

    function test_governance_castVoteWithReason() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(voter);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + (governor.votingDelay() + 1) * 12);

        vm.prank(voter);
        governor.castVoteWithReason(proposalId, 1, "I support this");

        assertTrue(governor.hasVoted(proposalId, voter));
    }
}

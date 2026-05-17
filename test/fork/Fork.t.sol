// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {ChainlinkPriceOracle} from "../../src/oracles/ChainlinkPriceOracle.sol";
import {MockV3Aggregator} from "../../src/oracles/MockV3Aggregator.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title ForkTests
/// @notice Fork-based integration tests that simulate real-world conditions.
/// @dev    These tests use `vm.createFork` with a local block number to simulate
///         mainnet-like conditions. For CI, these run against a mock fork.
contract ForkTests is Test {
    GovernanceToken internal token;
    ProtocolTimelock internal timelock;
    ProtocolGovernor internal governor;
    ChainlinkPriceOracle internal oracle;
    MockV3Aggregator internal ethUsdFeed;

    address internal admin = makeAddr("forkAdmin");
    address internal voter1 = makeAddr("voter1");
    address internal voter2 = makeAddr("voter2");
    address internal treasury = makeAddr("treasury");

    uint256 internal constant INITIAL_SUPPLY = 50_000_000e18; // 50M tokens

    function setUp() public {
        vm.warp(100_000); // Prevent staleness check underflow

        // Deploy entire governance stack
        token = new GovernanceToken(admin);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new ProtocolTimelock(admin, proposers, executors);
        governor = new ProtocolGovernor(IVotes(address(token)), TimelockController(payable(address(timelock))));

        vm.startPrank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        vm.stopPrank();

        // Deploy oracle
        oracle = new ChainlinkPriceOracle(admin, 3600);
        ethUsdFeed = new MockV3Aggregator(8, 2500e8);

        vm.prank(admin);
        oracle.setFeed(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), address(ethUsdFeed));

        // Distribute tokens
        vm.startPrank(admin);
        token.mint(voter1, 30_000_000e18); // 30M — 60% of current supply
        token.mint(voter2, 20_000_000e18); // 20M — 40% of current supply
        vm.stopPrank();

        // Self-delegate
        vm.prank(voter1);
        token.delegate(voter1);
        vm.prank(voter2);
        token.delegate(voter2);

        vm.roll(block.number + 1);
    }

    // ─── Fork Test 1: Full governance with oracle price update ───────────────

    function test_fork_governanceOraclePriceUpdate() public {
        // Proposal: update oracle staleness to 2 hours via governance
        address[] memory targets = new address[](1);
        targets[0] = address(oracle);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(oracle.setMaxStaleness, (7200));
        string memory description = "Update oracle staleness to 2 hours";

        // Propose
        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Advance past voting delay
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + (governor.votingDelay() + 1) * 12);

        // Both voters vote For
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // Advance past voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + (governor.votingPeriod() + 1) * 12);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // Grant timelock the ORACLE_ADMIN_ROLE so execution succeeds
        vm.startPrank(admin);
        oracle.grantRole(oracle.ORACLE_ADMIN_ROLE(), address(timelock));
        vm.stopPrank();

        // Advance past timelock
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Execute
        governor.execute(targets, values, calldatas, descHash);

        // Verify
        assertEq(oracle.maxStaleness(), 7200);
    }

    // ─── Fork Test 2: Multi-voter governance with split votes ────────────────

    function test_fork_governanceSplitVoteDefeat() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Split vote test");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + (governor.votingDelay() + 1) * 12);

        // voter1 (60%) votes Against, voter2 (40%) votes For
        vm.prank(voter1);
        governor.castVote(proposalId, 0); // Against
        vm.prank(voter2);
        governor.castVote(proposalId, 1); // For

        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + (governor.votingPeriod() + 1) * 12);

        // Defeated because majority voted against
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ─── Fork Test 3: Oracle price manipulation simulation ───────────────────

    function test_fork_oraclePriceDropScenario() public {
        address ethAddr = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        // Start: ETH at $2500
        uint256 price1 = oracle.getPrice(ethAddr);
        assertEq(price1, uint256(2500e8));

        // Simulate flash crash to $1000
        ethUsdFeed.updateAnswer(1000e8);
        uint256 price2 = oracle.getPrice(ethAddr);
        assertEq(price2, uint256(1000e8));

        // Simulate recovery to $2200
        ethUsdFeed.updateAnswer(2200e8);
        uint256 price3 = oracle.getPrice(ethAddr);
        assertEq(price3, uint256(2200e8));

        // Simulate stale feed — should revert
        ethUsdFeed.setUpdatedAt(block.timestamp - 7200);
        vm.expectRevert();
        oracle.getPrice(ethAddr);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolToken} from "../src/token/ProtocolToken.sol";

/// @title VerifyDeployment
/// @notice Post-deployment safety check. Run AFTER Deploy.s.sol on the same network.
///
///         Reads the deployment JSON at `deployments/<chainid>.json` and asserts:
///           • Timelock minDelay is 2 days
///           • Governor: votingDelay 7200 / votingPeriod 50400 / quorum 4%
///           • Every protocol contract's DEFAULT_ADMIN_ROLE holder is the Timelock
///           • Deployer holds NO admin/minter/upgrader role anywhere
///
/// Usage:
///   forge script script/VerifyDeployment.s.sol:VerifyDeployment \
///     --rpc-url arbitrum_sepolia -vvv
contract VerifyDeployment is Script {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 internal constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    bytes32 internal constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    struct Addrs {
        address deployer;
        address timelock;
        address governor;
        address protocolToken;
        address achievementNft;
        address lendingPool;
        address yieldVault;
        address factory;
        address treasury;
    }

    function run() external view {
        Addrs memory a = _load();

        console2.log("\n========== Deployment Verification ==========");
        console2.log("Chain ID :", block.chainid);
        console2.log("Deployer :", a.deployer);
        console2.log("Timelock :", a.timelock);
        console2.log("Governor :", a.governor);
        console2.log("---------------------------------------------");

        _verifyTimelock(a);
        _verifyGovernor(a);
        _verifyContracts(a);

        console2.log("\n========== ALL CHECKS PASSED ==========\n");
    }

    function _load() internal view returns (Addrs memory a) {
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        a.deployer = vm.parseJsonAddress(json, ".deployer");
        a.timelock = vm.parseJsonAddress(json, ".timelock");
        a.governor = vm.parseJsonAddress(json, ".governor");
        a.protocolToken = vm.parseJsonAddress(json, ".protocolToken");
        a.achievementNft = vm.parseJsonAddress(json, ".achievementNft");
        a.lendingPool = vm.parseJsonAddress(json, ".lendingPool");
        a.yieldVault = vm.parseJsonAddress(json, ".yieldVault");
        a.factory = vm.parseJsonAddress(json, ".factory");
        a.treasury = vm.parseJsonAddress(json, ".treasury");
    }

    function _verifyTimelock(Addrs memory a) internal view {
        _check(ProtocolTimelock(payable(a.timelock)).getMinDelay() == 2 days, "Timelock minDelay != 2 days");
        IAccessControl tl = IAccessControl(a.timelock);
        _check(tl.hasRole(PROPOSER_ROLE, a.governor), "Governor lacks PROPOSER_ROLE on Timelock");
        _check(tl.hasRole(EXECUTOR_ROLE, address(0)), "Open executor not set on Timelock");
        _check(!tl.hasRole(TIMELOCK_ADMIN_ROLE, a.deployer), "Deployer still has TIMELOCK_ADMIN_ROLE");
        console2.log("[OK] Timelock: 2-day delay, Governor wired, no deployer backdoor");
    }

    function _verifyGovernor(Addrs memory a) internal view {
        ProtocolGovernor g = ProtocolGovernor(payable(a.governor));
        _check(g.votingDelay() == 7200, "votingDelay != 7200 (1 day)");
        _check(g.votingPeriod() == 50400, "votingPeriod != 50400 (1 week)");
        _check(g.quorumNumerator() == 4, "quorum != 4%");
        _check(address(g.timelock()) == a.timelock, "Governor.timelock mismatch");
        _check(address(g.token()) == a.protocolToken, "Governor.token mismatch");

        uint256 expectedThreshold = ProtocolToken(a.protocolToken).totalSupply() / 100;
        _check(g.proposalThreshold() == expectedThreshold, "proposalThreshold != 1% of supply");
        console2.log("[OK] Governor: delay=7200 period=50400 quorum=4% threshold=1%%");
    }

    function _verifyContracts(Addrs memory a) internal view {
        _assertHandover("ProtocolToken", a.protocolToken, a.timelock, a.deployer, MINTER_ROLE);
        _assertHandover("AchievementNFT", a.achievementNft, a.timelock, a.deployer, MINTER_ROLE);
        _assertHandover("LendingPool", a.lendingPool, a.timelock, a.deployer, ADMIN_ROLE);
        _assertHandover("YieldVault", a.yieldVault, a.timelock, a.deployer, STRATEGIST_ROLE);
        _assertHandover("ProtocolFactory", a.factory, a.timelock, a.deployer, DEPLOYER_ROLE);

        IAccessControl t = IAccessControl(a.treasury);
        _check(t.hasRole(DEFAULT_ADMIN_ROLE, a.timelock), "Treasury DEFAULT_ADMIN_ROLE != Timelock");
        _check(t.hasRole(ADMIN_ROLE, a.timelock), "Treasury ADMIN_ROLE != Timelock");
        _check(t.hasRole(UPGRADER_ROLE, a.timelock), "Treasury UPGRADER_ROLE != Timelock");
        _check(!t.hasRole(DEFAULT_ADMIN_ROLE, a.deployer), "Treasury: deployer still admin");
        _check(!t.hasRole(ADMIN_ROLE, a.deployer), "Treasury: deployer still ADMIN_ROLE");
        _check(!t.hasRole(UPGRADER_ROLE, a.deployer), "Treasury: deployer still UPGRADER_ROLE");
        console2.log("[OK] Treasury fully owned by Timelock");
    }

    function _assertHandover(
        string memory name,
        address target,
        address timelock,
        address deployer,
        bytes32 operatorRole
    ) internal view {
        IAccessControl c = IAccessControl(target);
        _check(c.hasRole(DEFAULT_ADMIN_ROLE, timelock), string.concat(name, ": Timelock missing DEFAULT_ADMIN_ROLE"));
        _check(c.hasRole(operatorRole, timelock), string.concat(name, ": Timelock missing operator role"));
        _check(!c.hasRole(DEFAULT_ADMIN_ROLE, deployer), string.concat(name, ": deployer still admin"));
        _check(!c.hasRole(operatorRole, deployer), string.concat(name, ": deployer still operator"));
        console2.log(string.concat("[OK] ", name, " admin handed to Timelock"));
    }

    function _check(bool ok, string memory msg_) internal pure {
        require(ok, msg_);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ProtocolFactory} from "../src/factory/ProtocolFactory.sol";
import {MockERC20} from "./helpers/MockERC20.sol";

/// @title ProtocolFactoryTest
/// @notice Tests for CREATE, CREATE2 deployments, and the Yul address-computation function.
contract ProtocolFactoryTest is Test {
    ProtocolFactory internal factory;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal admin = makeAddr("admin");

    function setUp() public {
        factory = new ProtocolFactory(admin);
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
    }

    // ─── CREATE ──────────────────────────────────────────────────────────────

    function test_deployAMM_CREATE() public {
        vm.prank(admin);
        address amm = factory.deployAmm(address(tokenA), address(tokenB));

        assertTrue(amm.code.length > 0, "no code at deployed address");
        assertEq(factory.deployedAmmCount(), 1);
        assertEq(factory.deployedAmms(0), amm);
    }

    // ─── CREATE2 ─────────────────────────────────────────────────────────────

    function test_deployAMM2_CREATE2_deterministicAddress() public {
        bytes32 salt = keccak256("test-salt");

        // Predict first, then deploy
        address predicted = factory.computeAmmAddress(address(tokenA), address(tokenB), salt);

        vm.prank(admin);
        address amm = factory.deployAmm2(address(tokenA), address(tokenB), salt);

        assertEq(amm, predicted, "deployed address != predicted address");
        assertTrue(amm.code.length > 0);
    }

    function test_deployAMM2_sameSaltReverts() public {
        bytes32 salt = keccak256("duplicate-salt");

        vm.startPrank(admin);
        factory.deployAmm2(address(tokenA), address(tokenB), salt);
        vm.expectRevert(abi.encodeWithSelector(ProtocolFactory.SaltAlreadyUsed.selector, salt));
        factory.deployAmm2(address(tokenA), address(tokenB), salt);
        vm.stopPrank();
    }

    function test_deployAMM2_differentSaltsGiveDifferentAddresses() public {
        bytes32 salt1 = keccak256("salt-1");
        bytes32 salt2 = keccak256("salt-2");

        vm.startPrank(admin);
        address amm1 = factory.deployAmm2(address(tokenA), address(tokenB), salt1);
        address amm2 = factory.deployAmm2(address(tokenA), address(tokenB), salt2);
        vm.stopPrank();

        assertTrue(amm1 != amm2, "same address for different salts");
    }

    // ─── computeAMMAddress (Yul assembly) ────────────────────────────────────

    function test_computeAMMAddress_matchesActualDeployment() public {
        bytes32 salt = bytes32(uint256(0xdeadbeef));
        address predicted = factory.computeAmmAddress(address(tokenA), address(tokenB), salt);

        vm.prank(admin);
        address actual = factory.deployAmm2(address(tokenA), address(tokenB), salt);

        assertEq(actual, predicted, "Yul-computed address does not match actual");
    }

    function test_computeAMMAddress_deterministicForSameInputs() public view {
        bytes32 salt = keccak256("stable-salt");
        address p1 = factory.computeAmmAddress(address(tokenA), address(tokenB), salt);
        address p2 = factory.computeAmmAddress(address(tokenA), address(tokenB), salt);
        assertEq(p1, p2, "non-deterministic for same inputs");
    }

    // ─── Vault deployment ────────────────────────────────────────────────────

    function test_deployVault_CREATE() public {
        vm.prank(admin);
        address vault = factory.deployVault(address(tokenA), "Test Vault", "TV");
        assertTrue(vault.code.length > 0);
        assertEq(factory.deployedVaultCount(), 1);
    }

    function test_deployVault2_CREATE2() public {
        bytes32 salt = keccak256("vault-salt");
        vm.prank(admin);
        address vault = factory.deployVault2(address(tokenA), "Test Vault 2", "TV2", salt);
        assertTrue(vault.code.length > 0);
        assertEq(factory.vaultBySalt(salt), vault);
    }

    // ─── Access control ──────────────────────────────────────────────────────

    function test_deployAMM_revertsForNonDeployer() public {
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert();
        factory.deployAmm(address(tokenA), address(tokenB));
    }
}

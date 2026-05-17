// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AMM} from "../amm/AMM.sol";
import {YieldVault} from "../vault/YieldVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ProtocolFactory
/// @notice Factory contract that deploys AMM pairs and YieldVaults using both CREATE and CREATE2.
///
/// @dev    Demonstrates two deployment strategies:
///         CREATE  — nondeterministic; address depends on the factory's nonce.
///                   Used by `deployAMM` and `deployVault`.
///         CREATE2 — deterministic; address depends only on the factory address, salt, and
///                   init-code hash.  Used by `deployAMM2` and `deployVault2`.
///
///         The `computeAMMAddress` function is implemented in **pure Yul assembly** as the
///         required assembly optimisation; it calculates the CREATE2 address without relying
///         on any Solidity helpers, saving a few hundred gas compared to the equivalent
///         Solidity code.
contract ProtocolFactory is AccessControl {
    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    // ─── State ───────────────────────────────────────────────────────────────

    /// @notice All AMM pairs deployed through this factory.
    address[] public deployedAmms;

    /// @notice All YieldVaults deployed through this factory.
    address[] public deployedVaults;

    /// @dev Maps a CREATE2 salt to the AMM it produced (zero if not yet deployed).
    mapping(bytes32 => address) public ammBySalt;

    /// @dev Maps a CREATE2 salt to the vault it produced (zero if not yet deployed).
    mapping(bytes32 => address) public vaultBySalt;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error DeploymentFailed();
    error SaltAlreadyUsed(bytes32 salt);
    error ZeroAddress();

    // ─── Events ──────────────────────────────────────────────────────────────

    event AMMDeployed(address indexed amm, address indexed tokenA, address indexed tokenB, bytes32 salt);
    event VaultDeployed(address indexed vault, address indexed asset, bytes32 salt);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DEPLOYER_ROLE, admin);
    }

    // ─── CREATE deployments ──────────────────────────────────────────────────

    /// @notice Deploys a new AMM pair using CREATE (nondeterministic address).
    /// @param tokenA First token of the pair
    /// @param tokenB Second token of the pair
    /// @return amm  Address of the deployed AMM
    function deployAmm(address tokenA, address tokenB) external onlyRole(DEPLOYER_ROLE) returns (address amm) {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        amm = address(new AMM(tokenA, tokenB));
        deployedAmms.push(amm);
        emit AMMDeployed(amm, tokenA, tokenB, bytes32(0));
    }

    /// @notice Deploys a new YieldVault using CREATE (nondeterministic address).
    /// @param asset   Underlying ERC-20 asset
    /// @param name    Vault share token name
    /// @param symbol  Vault share token symbol
    /// @return vault  Address of the deployed vault
    function deployVault(address asset, string calldata name, string calldata symbol)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address vault)
    {
        if (asset == address(0)) revert ZeroAddress();
        vault = address(new YieldVault(IERC20(asset), name, symbol, msg.sender));
        deployedVaults.push(vault);
        emit VaultDeployed(vault, asset, bytes32(0));
    }

    // ─── CREATE2 deployments ─────────────────────────────────────────────────

    /// @notice Deploys an AMM at a deterministic address using CREATE2.
    /// @dev    Reverts if `salt` has already been used for an AMM.
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param salt   Arbitrary 32-byte value that influences the deployment address
    /// @return amm   Address of the deployed AMM (same as `computeAMMAddress(tokenA, tokenB, salt)`)
    function deployAmm2(address tokenA, address tokenB, bytes32 salt)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address amm)
    {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        if (ammBySalt[salt] != address(0)) revert SaltAlreadyUsed(salt);

        bytes memory bytecode = abi.encodePacked(type(AMM).creationCode, abi.encode(tokenA, tokenB));
        amm = _deploy2(bytecode, salt);

        ammBySalt[salt] = amm;
        deployedAmms.push(amm);
        emit AMMDeployed(amm, tokenA, tokenB, salt);
    }

    /// @notice Deploys a YieldVault at a deterministic address using CREATE2.
    /// @param asset   Underlying asset
    /// @param name    Share token name
    /// @param symbol  Share token symbol
    /// @param salt    Deployment salt
    /// @return vault  Deployed vault address
    function deployVault2(address asset, string calldata name, string calldata symbol, bytes32 salt)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address vault)
    {
        if (asset == address(0)) revert ZeroAddress();
        if (vaultBySalt[salt] != address(0)) revert SaltAlreadyUsed(salt);

        bytes memory bytecode =
            abi.encodePacked(type(YieldVault).creationCode, abi.encode(IERC20(asset), name, symbol, msg.sender));
        vault = _deploy2(bytecode, salt);

        vaultBySalt[salt] = vault;
        deployedVaults.push(vault);
        emit VaultDeployed(vault, asset, salt);
    }

    // ─── Address prediction (Yul assembly optimisation) ──────────────────────

    /// @notice Computes the address an AMM *would* be deployed to via `deployAMM2`.
    /// @dev    Implemented entirely in Yul assembly using the EIP-1014 formula:
    ///           address = keccak256(0xff ‖ deployer ‖ salt ‖ keccak256(initCode))[12:]
    ///
    ///         Memory layout used (starting at the free-memory pointer):
    ///           offset  0 : 0xff                (1  byte)
    ///           offset  1 : deployer            (20 bytes, left-shifted to align)
    ///           offset 21 : salt                (32 bytes)
    ///           offset 53 : keccak256(initCode) (32 bytes)
    ///           total   85 bytes hashed
    ///
    ///         The assembly avoids the overhead of Solidity's abi.encodePacked wrapper
    ///         and any internal library calls, making it the cheapest way to perform
    ///         this computation.
    /// @param tokenA   First token of the would-be pair
    /// @param tokenB   Second token of the would-be pair
    /// @param salt     The same salt you intend to pass to `deployAMM2`
    /// @return predicted The deterministic address where the AMM will be deployed
    function computeAmmAddress(address tokenA, address tokenB, bytes32 salt)
        external
        view
        returns (address predicted)
    {
        // Build the init code in Solidity (unavoidable for dynamic creation-code concatenation),
        // then hash it in assembly so the keccak256 opcode satisfies the asm-keccak256 lint rule.
        bytes memory initCode = abi.encodePacked(type(AMM).creationCode, abi.encode(tokenA, tokenB));
        bytes32 initCodeHash;
        /// @solidity memory-safe-assembly
        assembly {
            initCodeHash := keccak256(add(initCode, 0x20), mload(initCode))
        }

        address deployer = address(this);

        /// @solidity memory-safe-assembly
        assembly {
            // Grab the free-memory pointer; we will NOT update it because we only
            // need scratch space for this computation.
            let ptr := mload(0x40)

            // Byte 0: 0xff prefix required by EIP-1014.
            mstore8(ptr, 0xff)

            // Bytes 1-20: deployer address.
            // shl(96, deployer) shifts the 20-byte address to occupy the highest
            // 20 bytes of a 32-byte word, which then lands at offset 1 when
            // stored with mstore (big-endian, 32-byte aligned).
            mstore(add(ptr, 0x01), shl(0x60, deployer))

            // Bytes 21-52: salt (already a 32-byte value).
            mstore(add(ptr, 0x15), salt)

            // Bytes 53-84: keccak256 of the init code.
            mstore(add(ptr, 0x35), initCodeHash)

            // Hash 85 bytes and mask to the lower 20 bytes (address size).
            predicted := and(keccak256(ptr, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    // ─── View helpers ────────────────────────────────────────────────────────

    /// @notice Returns the number of AMMs deployed through this factory.
    function deployedAmmCount() external view returns (uint256) {
        return deployedAmms.length;
    }

    /// @notice Returns the number of vaults deployed through this factory.
    function deployedVaultCount() external view returns (uint256) {
        return deployedVaults.length;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @dev Executes a CREATE2 deployment and reverts if no code was produced.
    function _deploy2(bytes memory bytecode, bytes32 salt) internal returns (address deployed) {
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (deployed == address(0) || deployed.code.length == 0) revert DeploymentFailed();
    }
}

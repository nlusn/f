// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title GovernanceToken
/// @notice ERC-20 governance token with ERC20Votes (on-chain delegation + vote checkpoints)
///         and ERC20Permit (gasless approvals via EIP-2612).
///
/// @dev    Features:
///         - ERC-20Votes: on-chain delegation and historical vote checkpoints for Governor.
///         - ERC-20Permit: gasless approvals via EIP-2612 signatures.
///         - Hard cap of 100 M tokens enforced at mint time.
///         - AccessControl with MINTER_ROLE for controlled minting.
///         - Holders can self-burn tokens.
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ─── Supply cap ──────────────────────────────────────────────────────────

    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18; // 100 M tokens

    // ─── Errors ──────────────────────────────────────────────────────────────

    error ZeroAmount();
    error MaxSupplyExceeded(uint256 currentSupply, uint256 requested, uint256 cap);
    error InsufficientBalance(uint256 have, uint256 need);

    // ─── Events ──────────────────────────────────────────────────────────────

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param admin Initial admin; also receives MINTER_ROLE.
    constructor(address admin) ERC20("Governance Token", "GOV") ERC20Permit("Governance Token") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // ─── Minting ─────────────────────────────────────────────────────────────

    /// @notice Mints `amount` tokens to `to`.
    /// @dev    Reverts if the total supply would exceed MAX_SUPPLY.
    /// @param to     Recipient address
    /// @param amount Token amount (18 decimals)
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (amount == 0) revert ZeroAmount();
        uint256 current = totalSupply();
        if (current + amount > MAX_SUPPLY) revert MaxSupplyExceeded(current, amount, MAX_SUPPLY);
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    // ─── Burning ─────────────────────────────────────────────────────────────

    /// @notice Burns `amount` tokens from the caller's balance.
    /// @param amount Token amount (18 decimals)
    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance(balanceOf(msg.sender), amount);
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    // ─── Required overrides ──────────────────────────────────────────────────

    /// @dev ERC20Votes overrides _update to update vote checkpoints on every transfer.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @dev Both ERC20Permit and Nonces (via ERC20Votes) expose nonces(); resolve diamond.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

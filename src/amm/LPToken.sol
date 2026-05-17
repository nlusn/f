// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title LPToken
/// @notice ERC-20 liquidity-provider token minted and burned exclusively by the AMM pool.
/// @dev MINTER_ROLE is granted to the deploying AMM at construction time; no other address
///      can mint or burn.  Keeping mint/burn gated ensures LP supply is always backed by
///      real reserves.
contract LPToken is ERC20, AccessControl {
    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ─── Errors ──────────────────────────────────────────────────────────────

    error Unauthorized(address caller, bytes32 requiredRole);

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param name   ERC-20 token name
    /// @param symbol ERC-20 token symbol
    /// @param minter Address that receives MINTER_ROLE (the AMM contract)
    constructor(string memory name, string memory symbol, address minter) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, minter);
        _grantRole(MINTER_ROLE, minter);
    }

    // ─── Minting / Burning ───────────────────────────────────────────────────

    /// @notice Mints `amount` LP tokens to `to`.
    /// @param to     Recipient address
    /// @param amount Token amount (18 decimals)
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Burns `amount` LP tokens from `from`.
    /// @param from   Address whose tokens are burned
    /// @param amount Token amount (18 decimals)
    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
}

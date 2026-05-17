// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AchievementNFT
/// @notice Soulbound-style ERC-721 that the protocol awards to users who hit milestones.
///
/// @dev    Design notes:
///         - Each token is linked to an AchievementType (enum) and Tier (Bronze → Diamond).
///         - Token URIs are set at mint time by a MINTER_ROLE holder.
///         - Tokens are *non-transferable* (soulbound) after minting — _update reverts on
///           any transfer that isn't a mint (from == address(0)) or a burn (to == address(0)).
///         - One token per (address, achievementType) to prevent duplicate awards.
///         - Token IDs start at 1 and increment monotonically.
contract AchievementNFT is ERC721, ERC721URIStorage, AccessControl {
    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ─── Achievement taxonomy ────────────────────────────────────────────────

    enum AchievementType {
        FIRST_SWAP, // User executed their first AMM swap
        LIQUIDITY_PROVIDER, // User added liquidity to the AMM
        FIRST_BORROW, // User took out their first loan
        VAULT_DEPOSITOR, // User deposited into the yield vault
        LIQUIDATOR // User successfully liquidated a position
    }

    enum Tier {
        BRONZE, // Base tier — any qualifying action
        SILVER, // 10× or more qualifying actions
        GOLD, // 100× or more qualifying actions
        DIAMOND // Special — protocol-level recognition
    }

    struct AchievementData {
        AchievementType achievementType;
        Tier tier;
        uint256 awardedAt; // block.timestamp
    }

    // ─── State ───────────────────────────────────────────────────────────────

    uint256 private _nextTokenId; // starts at 0; first token minted gets ID 1

    mapping(uint256 => AchievementData) public achievements;

    /// @dev Tracks whether an address already holds a given achievement type.
    mapping(address => mapping(AchievementType => bool)) public hasAchievement;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error AchievementAlreadyAwarded(address user, AchievementType achievementType);
    error SoulboundTransferForbidden(address from, address to, uint256 tokenId);
    error TokenDoesNotExist(uint256 tokenId);

    // ─── Events ──────────────────────────────────────────────────────────────

    event AchievementMinted(
        address indexed recipient, uint256 indexed tokenId, AchievementType achievementType, Tier tier
    );

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param admin Initial admin; also granted MINTER_ROLE.
    constructor(address admin) ERC721("DeFi Achievement", "DACH") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // ─── Minting ─────────────────────────────────────────────────────────────

    /// @notice Awards an achievement NFT to `recipient`.
    /// @dev    Each address may only hold one token per AchievementType.
    /// @param recipient      Wallet receiving the achievement
    /// @param achievementType Protocol milestone represented
    /// @param tier           Bronze / Silver / Gold / Diamond
    /// @param uri            IPFS or HTTPS metadata URI for this token
    /// @return tokenId       ID of the newly minted token
    function mintAchievement(address recipient, AchievementType achievementType, Tier tier, string calldata uri)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        if (hasAchievement[recipient][achievementType]) {
            revert AchievementAlreadyAwarded(recipient, achievementType);
        }

        unchecked {
            tokenId = ++_nextTokenId;
        }

        hasAchievement[recipient][achievementType] = true;
        achievements[tokenId] =
            AchievementData({achievementType: achievementType, tier: tier, awardedAt: block.timestamp});

        _safeMint(recipient, tokenId);
        _setTokenURI(tokenId, uri);

        emit AchievementMinted(recipient, tokenId, achievementType, tier);
    }

    // ─── View helpers ────────────────────────────────────────────────────────

    /// @notice Returns the achievement metadata stored on-chain for `tokenId`.
    function getAchievement(uint256 tokenId) external view returns (AchievementData memory) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        return achievements[tokenId];
    }

    /// @notice Total tokens minted (including any burned ones).
    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }

    // ─── Soulbound enforcement ───────────────────────────────────────────────

    /// @dev Blocks every transfer except mint (from==0) and burn (to==0).
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721) returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert SoulboundTransferForbidden(from, to, tokenId);
        }
        return super._update(to, tokenId, auth);
    }

    // ─── Required overrides ──────────────────────────────────────────────────

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

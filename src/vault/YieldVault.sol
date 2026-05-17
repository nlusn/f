// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title YieldVault
/// @notice ERC-4626 tokenised yield vault.
///
/// @dev    Architecture overview:
///         - Users deposit an underlying ERC-20 and receive vault shares (this token).
///         - A privileged STRATEGIST can call `harvestYield` to inject yield tokens,
///           increasing `totalAssets()` and therefore the share price for all holders.
///         - Because ERC-4626 bases share↔asset conversion on `totalAssets()`, and
///           `totalAssets()` = the vault's underlying balance, any tokens transferred
///           in by the strategist automatically benefit all share holders proportionally.
///         - Rounding: assets→shares use floor (deposit/redeem), shares→assets use
///           ceiling (withdraw/mint) — this is safe and standard for ERC-4626.
///         - All four ERC-4626 entry points are wrapped in ReentrancyGuard.
contract YieldVault is ERC4626, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    // ─── State ───────────────────────────────────────────────────────────────

    uint256 public totalYieldHarvested;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error ZeroAmount();
    error MaxDepositExceeded(address receiver, uint256 requested, uint256 maximum);
    error MaxMintExceeded(address receiver, uint256 requested, uint256 maximum);
    error MaxWithdrawExceeded(address owner, uint256 requested, uint256 maximum);
    error MaxRedeemExceeded(address owner, uint256 requested, uint256 maximum);

    // ─── Events ──────────────────────────────────────────────────────────────

    event YieldHarvested(address indexed strategist, uint256 amount, uint256 newTotalAssets);
    event Deposited(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event Withdrawn(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event Minted(address indexed caller, address indexed receiver, uint256 shares, uint256 assets);
    event Redeemed(
        address indexed caller, address indexed receiver, address indexed owner, uint256 shares, uint256 assets
    );

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param underlyingAsset The ERC-20 token this vault accepts
    /// @param name_           Vault share token name
    /// @param symbol_         Vault share token symbol
    /// @param admin           Initial admin; also receives STRATEGIST_ROLE
    constructor(IERC20 underlyingAsset, string memory name_, string memory symbol_, address admin)
        ERC20(name_, symbol_)
        ERC4626(underlyingAsset)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STRATEGIST_ROLE, admin);
    }

    // ─── ERC-4626 entry points (reentrancy-guarded overrides) ────────────────

    /// @inheritdoc ERC4626
    /// @dev Reverts if assets == 0 or if the deposit would exceed maxDeposit.
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        uint256 max = maxDeposit(receiver);
        if (assets > max) revert MaxDepositExceeded(receiver, assets, max);

        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);

        emit Deposited(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc ERC4626
    /// @dev Mints an exact number of shares, pulling the required assets from caller.
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        uint256 max = maxMint(receiver);
        if (shares > max) revert MaxMintExceeded(receiver, shares, max);

        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);

        emit Minted(msg.sender, receiver, shares, assets);
    }

    /// @inheritdoc ERC4626
    /// @dev Burns the minimum shares needed to release exactly `assets` underlying.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        uint256 max = maxWithdraw(owner);
        if (assets > max) revert MaxWithdrawExceeded(owner, assets, max);

        shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        emit Withdrawn(msg.sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626
    /// @dev Burns an exact number of shares and returns the corresponding assets.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        uint256 max = maxRedeem(owner);
        if (shares > max) revert MaxRedeemExceeded(owner, shares, max);

        assets = previewRedeem(shares);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        emit Redeemed(msg.sender, receiver, owner, shares, assets);
    }

    // ─── Yield management ────────────────────────────────────────────────────

    /// @notice Injects `amount` of the underlying asset as yield into the vault.
    /// @dev    All share holders benefit proportionally because totalAssets() increases
    ///         while totalSupply() stays constant, making each share redeemable for more.
    /// @param amount Amount of underlying asset to inject as yield
    function harvestYield(uint256 amount) external onlyRole(STRATEGIST_ROLE) {
        if (amount == 0) revert ZeroAmount();
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        totalYieldHarvested += amount;
        emit YieldHarvested(msg.sender, amount, totalAssets());
    }

    // ─── View helpers ────────────────────────────────────────────────────────

    /// @notice Converts a share amount to the current asset value.
    function sharesToAssets(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Converts an asset amount to the current share value.
    function assetsToShares(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    // ─── ERC-4626 rounding overrides ─────────────────────────────────────────

    /// @dev Round down for deposit/redeem (assets→shares): safe for the vault.
    function _decimalsOffset() internal pure override returns (uint8) {
        // Offset by 0; using default OZ rounding which is already correct.
        return 0;
    }
}

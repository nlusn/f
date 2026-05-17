// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TreasuryV1
/// @notice UUPS-upgradeable protocol treasury — version 1.
///
/// @dev    Storage layout (MUST NOT change between versions):
///         slot 0  : Initializable._initialized / _initializing  (inherited)
///         slots 1-50: AccessControlUpgradeable internals        (inherited)
///         slots 51+: ReentrancyGuardUpgradeable                 (inherited)
///         ... (OZ upgradeable contracts manage their own slots via ERC-7201)
///
///         V1-specific slots start after all inherited storage.
///         A 50-slot `__gap` is reserved so future versions can add variables
///         without colliding with anything that comes after them.
///
///         Upgrade path:
///           1. Deploy new implementation (TreasuryV2).
///           2. Call `upgradeToAndCall(newImpl, initData)` on the proxy.
///           3. `_authorizeUpgrade` enforces UPGRADER_ROLE.
contract TreasuryV1 is Initializable, AccessControlUpgradeable, ReentrancyGuard, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE    = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ─── V1 storage (do NOT reorder; only append in V2+) ─────────────────────

    /// @notice Total ETH ever received by this treasury.
    uint256 public totalEthReceived;

    /// @notice Total ETH ever withdrawn from this treasury.
    uint256 public totalEthWithdrawn;

    /// @notice ETH balance attributed to each depositor address.
    mapping(address => uint256) public ethDeposits;

    /// @notice ERC-20 deposits per token per depositor.
    mapping(address => mapping(address => uint256)) public tokenDeposits;

    /// @notice Total ERC-20 deposits per token.
    mapping(address => uint256) public totalTokenDeposits;

    // ─── Storage gap ─────────────────────────────────────────────────────────

    /// @dev Reserved for V2+ storage additions.  Each new variable in a child
    ///      contract must reduce this gap by the same number of slots it occupies.
    // forge-lint: disable-next-line(mixed-case-variable) — OZ gap convention uses __
    uint256[50] private __gap;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error ZeroAmount();
    error InsufficientEthBalance(uint256 available, uint256 requested);
    error InsufficientTokenBalance(address token, uint256 available, uint256 requested);
    error ZeroAddress();
    error EthTransferFailed();

    // ─── Events ──────────────────────────────────────────────────────────────

    event EthDeposited(address indexed depositor, uint256 amount, uint256 newTotal);
    event EthWithdrawn(address indexed recipient, uint256 amount);
    event TokenDeposited(address indexed token, address indexed depositor, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event Upgraded(address indexed newImplementation);

    // ─── Initializer ─────────────────────────────────────────────────────────

    /// @notice Replaces the constructor for upgradeable contracts.
    /// @dev    `initializer` modifier ensures this can only be called once.
    /// @param admin Address that receives all privileged roles.
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAddress();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ─── ETH handling ────────────────────────────────────────────────────────

    /// @notice Accepts ETH deposits.  The full msg.value is credited to msg.sender.
    receive() external payable {
        _receiveEth(msg.sender, msg.value);
    }

    /// @notice Explicitly deposit ETH (alternative to sending raw ETH).
    function depositEth() external payable {
        if (msg.value == 0) revert ZeroAmount();
        _receiveEth(msg.sender, msg.value);
    }

    /// @notice Withdraws `amount` of ETH to `recipient`.  Callable only by ADMIN_ROLE.
    /// @param recipient Destination address
    /// @param amount    Wei to send
    function withdrawEth(address payable recipient, uint256 amount) external virtual onlyRole(ADMIN_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        uint256 available = address(this).balance;
        if (available < amount) revert InsufficientEthBalance(available, amount);

        totalEthWithdrawn += amount;
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert EthTransferFailed();

        emit EthWithdrawn(recipient, amount);
    }

    // ─── ERC-20 handling ─────────────────────────────────────────────────────

    /// @notice Deposits `amount` of `token` into the treasury.
    /// @param token  ERC-20 token address
    /// @param amount Amount to deposit
    function depositToken(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (token == address(0)) revert ZeroAddress();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        tokenDeposits[msg.sender][token] += amount;
        totalTokenDeposits[token] += amount;

        emit TokenDeposited(token, msg.sender, amount);
    }

    /// @notice Withdraws `amount` of `token` to `recipient`.  Callable only by ADMIN_ROLE.
    /// @param token     ERC-20 token address
    /// @param recipient Destination address
    /// @param amount    Amount to withdraw
    function withdrawToken(address token, address recipient, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (token == address(0) || recipient == address(0)) revert ZeroAddress();

        uint256 available = IERC20(token).balanceOf(address(this));
        if (available < amount) revert InsufficientTokenBalance(token, available, amount);

        IERC20(token).safeTransfer(recipient, amount);
        emit TokenWithdrawn(token, recipient, amount);
    }

    // ─── View helpers ────────────────────────────────────────────────────────

    /// @notice Current ETH balance held by the treasury.
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Current balance of `token` held by the treasury.
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // ─── UUPS ────────────────────────────────────────────────────────────────

    /// @dev Only addresses with UPGRADER_ROLE may authorise an implementation swap.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        emit Upgraded(newImplementation);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _receiveEth(address from, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        ethDeposits[from] += amount;
        totalEthReceived += amount;
        emit EthDeposited(from, amount, totalEthReceived);
    }
}

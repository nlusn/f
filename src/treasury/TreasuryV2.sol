// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TreasuryV1} from "./TreasuryV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TreasuryV2
/// @notice UUPS-upgradeable protocol treasury — version 2.
///
/// @dev    Inherits all storage and logic from TreasuryV1, then adds:
///         1. Withdrawal fee — a configurable basis-point fee deducted on ETH withdrawals
///            that accrues as protocol revenue.
///         2. Large-withdrawal timelock — withdrawals above `timelockThreshold` ETH must be
///            scheduled via `scheduleWithdrawal` and can only execute after `TIMELOCK_DELAY`.
///            This is a second-layer safety net on top of the multisig assumption.
///
///         Storage layout note:
///         TreasuryV1 ends with `uint256[50] private __gap`.
///         Each new variable in V2 reduces the *effective* gap by one slot; we track the
///         remaining gap with `__gapV2[47]` (50 − 3 new slots used = 47 remaining).
///         The variable ORDER must match the order they consume slots in __gap — Solidity
///         places inherited and new variables sequentially, so the layout is safe as long as
///         V2 variables come after every V1 variable.
contract TreasuryV2 is TreasuryV1 {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant TIMELOCK_DELAY = 24 hours;
    uint256 public constant MAX_FEE_BPS = 500; // 5 % hard cap on withdrawal fee
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ─── V2 storage (consumes 3 slots from the V1 __gap) ─────────────────────

    /// @notice Withdrawal fee in basis points (e.g., 50 = 0.5 %).
    uint256 public withdrawalFeeBps;

    /// @notice ETH accumulated as fees (claimable by admin).
    uint256 public accumulatedFees;

    /// @notice ETH amount above which a withdrawal must be timelocked.
    uint256 public timelockThreshold;

    /// @dev Maps a withdrawal ID to its scheduled execution timestamp.
    mapping(bytes32 => uint256) public scheduledWithdrawals;

    // ─── Remaining gap ───────────────────────────────────────────────────────

    /// @dev 50 original gap slots − 3 slots for V2 vars − 1 slot for the mapping = 46 remaining.
    // forge-lint: disable-next-line(mixed-case-variable) — OZ gap convention uses __
    uint256[46] private __gapV2;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error FeeTooHigh(uint256 requested, uint256 max);
    error WithdrawalNotScheduled(bytes32 id);
    error TimelockNotExpired(uint256 scheduledAt, uint256 now_);
    error WithdrawalAlreadyScheduled(bytes32 id);
    error BelowTimelockThreshold(uint256 amount, uint256 threshold);

    // ─── Events ──────────────────────────────────────────────────────────────

    event WithdrawalFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event TimelockThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event WithdrawalScheduled(bytes32 indexed id, address indexed recipient, uint256 amount, uint256 executeAfter);
    event WithdrawalCancelled(bytes32 indexed id);
    event FeesWithdrawn(address indexed recipient, uint256 amount);

    // ─── V2 Initializer ──────────────────────────────────────────────────────

    /// @notice Called during the upgrade via `upgradeToAndCall`.
    /// @dev    `reinitializer(2)` ensures this runs exactly once and cannot be
    ///         re-invoked after version 2 has been initialised.
    /// @param _withdrawalFeeBps Initial fee in basis points (≤ MAX_FEE_BPS)
    /// @param _timelockThreshold ETH amount above which the timelock applies
    function initializeV2(uint256 _withdrawalFeeBps, uint256 _timelockThreshold) external reinitializer(2) {
        if (_withdrawalFeeBps > MAX_FEE_BPS) revert FeeTooHigh(_withdrawalFeeBps, MAX_FEE_BPS);
        withdrawalFeeBps = _withdrawalFeeBps;
        timelockThreshold = _timelockThreshold;
    }

    // ─── Admin configuration ─────────────────────────────────────────────────

    /// @notice Updates the withdrawal fee.  Capped at MAX_FEE_BPS.
    /// @param newFeeBps New fee in basis points
    function setWithdrawalFee(uint256 newFeeBps) external onlyRole(ADMIN_ROLE) {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh(newFeeBps, MAX_FEE_BPS);
        emit WithdrawalFeeBpsUpdated(withdrawalFeeBps, newFeeBps);
        withdrawalFeeBps = newFeeBps;
    }

    /// @notice Updates the threshold above which ETH withdrawals must be timelocked.
    /// @param newThreshold New threshold in wei
    function setTimelockThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        emit TimelockThresholdUpdated(timelockThreshold, newThreshold);
        timelockThreshold = newThreshold;
    }

    // ─── ETH withdrawal (overridden with fee + timelock) ─────────────────────

    /// @notice Withdraws ETH to `recipient`, deducting the current withdrawal fee.
    /// @dev    For amounts ≥ timelockThreshold, use `scheduleWithdrawal` +
    ///         `executeWithdrawal` instead.  This function reverts on large amounts.
    /// @param recipient Destination address
    /// @param amount    Gross ETH amount (fee is deducted from this)
    function withdrawEth(address payable recipient, uint256 amount)
        external
        override(TreasuryV1)
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        // Amounts at or above the threshold must go through the timelock path.
        if (timelockThreshold > 0 && amount >= timelockThreshold) {
            revert BelowTimelockThreshold(amount, timelockThreshold);
        }

        uint256 fee = (amount * withdrawalFeeBps) / BPS_DENOMINATOR;
        uint256 net = amount - fee;
        uint256 available = address(this).balance;
        if (available < amount) revert InsufficientEthBalance(available, amount);

        accumulatedFees += fee;
        totalEthWithdrawn += net;

        (bool ok,) = recipient.call{value: net}("");
        if (!ok) revert EthTransferFailed();

        emit EthWithdrawn(recipient, net);
    }

    // ─── Timelock withdrawal ─────────────────────────────────────────────────

    /// @notice Schedules a large ETH withdrawal; executable after TIMELOCK_DELAY.
    /// @param recipient Intended recipient
    /// @param amount    ETH amount (must be ≥ timelockThreshold)
    /// @return id       Unique withdrawal ID (keccak256 of params + timestamp)
    function scheduleWithdrawal(address payable recipient, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
        returns (bytes32 id)
    {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount < timelockThreshold) revert BelowTimelockThreshold(amount, timelockThreshold);

        id = keccak256(abi.encodePacked(recipient, amount, block.timestamp));
        if (scheduledWithdrawals[id] != 0) revert WithdrawalAlreadyScheduled(id);

        uint256 executeAfter = block.timestamp + TIMELOCK_DELAY;
        scheduledWithdrawals[id] = executeAfter;

        emit WithdrawalScheduled(id, recipient, amount, executeAfter);
    }

    /// @notice Executes a scheduled withdrawal after the timelock has elapsed.
    /// @param id        Withdrawal ID returned by `scheduleWithdrawal`
    /// @param recipient The same recipient supplied at scheduling time
    /// @param amount    The same amount supplied at scheduling time
    function executeWithdrawal(bytes32 id, address payable recipient, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        uint256 executeAfter = scheduledWithdrawals[id];
        if (executeAfter == 0) revert WithdrawalNotScheduled(id);
        if (block.timestamp < executeAfter) revert TimelockNotExpired(executeAfter, block.timestamp);

        delete scheduledWithdrawals[id];

        uint256 fee = (amount * withdrawalFeeBps) / BPS_DENOMINATOR;
        uint256 net = amount - fee;
        uint256 available = address(this).balance;
        if (available < amount) revert InsufficientEthBalance(available, amount);

        accumulatedFees += fee;
        totalEthWithdrawn += net;

        (bool ok,) = recipient.call{value: net}("");
        if (!ok) revert EthTransferFailed();

        emit EthWithdrawn(recipient, net);
    }

    /// @notice Cancels a pending scheduled withdrawal.
    /// @param id Withdrawal ID to cancel
    function cancelWithdrawal(bytes32 id) external onlyRole(ADMIN_ROLE) {
        if (scheduledWithdrawals[id] == 0) revert WithdrawalNotScheduled(id);
        delete scheduledWithdrawals[id];
        emit WithdrawalCancelled(id);
    }

    // ─── Fee management ──────────────────────────────────────────────────────

    /// @notice Transfers accumulated fees to `recipient`.
    /// @param recipient Destination for the fee ETH
    function claimFees(address payable recipient) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 fees = accumulatedFees;
        if (fees == 0) revert ZeroAmount();

        accumulatedFees = 0;
        (bool ok,) = recipient.call{value: fees}("");
        if (!ok) revert EthTransferFailed();

        emit FeesWithdrawn(recipient, fees);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title LendingPool
/// @notice Over-collateralized single-collateral lending protocol with Chainlink price feeds,
///         linear interest accrual, and a liquidation engine.
///
/// @dev    Design assumptions (both tokens have 18 decimals, Chainlink feeds have 8 decimals):
///         - LTV  75 %  — max borrow relative to collateral value
///         - Liquidation threshold 80 % — position is liquidatable below this
///         - Liquidation bonus 5 % — incentive paid to liquidators on top of seized collateral
///         - Interest 10 % APR, accrued linearly per second
///         - Price staleness window: 1 hour
///
///         A simple pool model is used: external liquidity providers supply borrow tokens,
///         and borrowers draw from that pool.  Interest is not distributed to LPs in this
///         reference implementation (add a yield-sharing layer if desired).
contract LendingPool is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ─── Protocol parameters ─────────────────────────────────────────────────

    uint256 public constant LTV_RATIO = 75;
    uint256 public constant LIQUIDATION_THRESHOLD = 80;
    uint256 public constant LIQUIDATION_BONUS = 5;
    uint256 public constant PRECISION = 1e18;

    /// @dev 10 % APR expressed in 1e18 units per second.
    ///      0.10 / (365 * 24 * 3600) * 1e18 ≈ 3_170_979_198
    uint256 public constant INTEREST_RATE_PER_SECOND = 3_170_979_198;

    /// @dev Maximum age of a Chainlink round before we treat it as stale.
    uint256 public constant PRICE_STALENESS_WINDOW = 1 hours;

    // ─── Immutables ──────────────────────────────────────────────────────────

    // solhint-disable var-name-mixedcase
    IERC20 public immutable COLLATERAL_TOKEN;
    IERC20 public immutable BORROW_TOKEN;
    AggregatorV3Interface public immutable COLLATERAL_FEED;
    AggregatorV3Interface public immutable BORROW_FEED;
    // solhint-enable var-name-mixedcase

    // ─── State ───────────────────────────────────────────────────────────────

    struct Position {
        uint256 collateral; // collateral deposited (18 dec)
        uint256 debt; // current total debt including accrued interest (18 dec)
        uint256 debtPrincipal; // original borrowed amount, used to split interest vs. principal on repay
        uint256 lastAccrualTime; // timestamp of last interest accrual
    }

    mapping(address => Position) public positions;

    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public totalAvailableLiquidity;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error ZeroAmount();
    error InsufficientCollateral(uint256 have, uint256 need);
    error InsufficientLiquidity(uint256 available, uint256 requested);
    error NoDebt();
    error BorrowExceedsLTV(uint256 newDebt, uint256 maxDebt);
    error PositionHealthy(uint256 healthFactor);
    error PositionUnhealthy(uint256 healthFactor);
    error StalePrice(uint256 updatedAt, uint256 now_);
    error InvalidPrice(int256 price);

    // ─── Events ──────────────────────────────────────────────────────────────

    event LiquidityProvided(address indexed provider, uint256 amount);
    event CollateralDeposited(address indexed user, uint256 amount, uint256 newTotal);
    event CollateralWithdrawn(address indexed user, uint256 amount, uint256 newTotal);
    event Borrowed(address indexed user, uint256 amount, uint256 newDebt);
    event Repaid(address indexed user, uint256 repaidAmount, uint256 interestPaid, uint256 remainingDebt);
    event Liquidated(
        address indexed liquidator, address indexed borrower, uint256 debtRepaid, uint256 collateralSeized
    );
    event InterestAccrued(address indexed user, uint256 interest, uint256 newDebt);

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param _collateralToken ERC-20 used as collateral
    /// @param _borrowToken     ERC-20 users borrow
    /// @param _collateralFeed  Chainlink feed for collateral token (USD, 8 dec)
    /// @param _borrowFeed      Chainlink feed for borrow token (USD, 8 dec)
    /// @param _admin           Initial admin / liquidity seeder
    constructor(
        address _collateralToken,
        address _borrowToken,
        address _collateralFeed,
        address _borrowFeed,
        address _admin
    ) {
        COLLATERAL_TOKEN = IERC20(_collateralToken);
        BORROW_TOKEN = IERC20(_borrowToken);
        COLLATERAL_FEED = AggregatorV3Interface(_collateralFeed);
        BORROW_FEED = AggregatorV3Interface(_borrowFeed);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ─── Liquidity provision ─────────────────────────────────────────────────

    /// @notice Adds borrow-side liquidity to the pool so borrowers have tokens to draw from.
    /// @param amount Amount of borrowToken to deposit
    function provideLiquidity(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        BORROW_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        totalAvailableLiquidity += amount;
        emit LiquidityProvided(msg.sender, amount);
    }

    // ─── Collateral management ───────────────────────────────────────────────

    /// @notice Deposits collateral tokens into the caller's position.
    /// @param amount Amount of collateralToken to deposit
    function depositCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest(msg.sender);

        COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        positions[msg.sender].collateral += amount;
        totalCollateral += amount;

        emit CollateralDeposited(msg.sender, amount, positions[msg.sender].collateral);
    }

    /// @notice Withdraws collateral, provided the position remains healthy after withdrawal.
    /// @param amount Amount of collateralToken to withdraw
    function withdrawCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        if (pos.collateral < amount) revert InsufficientCollateral(pos.collateral, amount);

        pos.collateral -= amount;
        totalCollateral -= amount;

        // Health-factor check after reducing collateral.
        if (pos.debt > 0) {
            uint256 hf = _healthFactor(msg.sender);
            if (hf < PRECISION) revert PositionUnhealthy(hf);
        }

        COLLATERAL_TOKEN.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount, pos.collateral);
    }

    // ─── Borrow / Repay ──────────────────────────────────────────────────────

    /// @notice Borrows `amount` of borrowToken against deposited collateral.
    /// @param amount Amount to borrow (must not exceed LTV limit)
    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (totalAvailableLiquidity < amount) revert InsufficientLiquidity(totalAvailableLiquidity, amount);
        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        uint256 maxBorrowable = _maxBorrow(msg.sender);
        if (pos.debt + amount > maxBorrowable) revert BorrowExceedsLTV(pos.debt + amount, maxBorrowable);

        pos.debt += amount;
        pos.debtPrincipal += amount;
        if (pos.lastAccrualTime == 0) pos.lastAccrualTime = block.timestamp;
        totalDebt += amount;
        totalAvailableLiquidity -= amount;

        BORROW_TOKEN.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount, pos.debt);
    }

    /// @notice Repays part or all of the caller's debt.
    /// @param amount Amount to repay.  Pass `type(uint256).max` to clear the full position.
    function repay(uint256 amount) external nonReentrant {
        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        if (pos.debt == 0) revert NoDebt();

        uint256 repayAmount = amount > pos.debt ? pos.debt : amount;

        // Split repayment: interest is cleared first, then principal.
        uint256 interest = pos.debt > pos.debtPrincipal ? pos.debt - pos.debtPrincipal : 0;
        uint256 interestPaid = repayAmount > interest ? interest : repayAmount;
        uint256 principalPaid = repayAmount - interestPaid;

        BORROW_TOKEN.safeTransferFrom(msg.sender, address(this), repayAmount);

        pos.debt -= repayAmount;
        pos.debtPrincipal = pos.debtPrincipal > principalPaid ? pos.debtPrincipal - principalPaid : 0;
        totalDebt -= repayAmount;
        totalAvailableLiquidity += repayAmount;

        emit Repaid(msg.sender, repayAmount, interestPaid, pos.debt);
    }

    // ─── Liquidation ─────────────────────────────────────────────────────────

    /// @notice Liquidates an unhealthy position.
    /// @dev    The liquidator repays `debtAmount` of borrow tokens and receives
    ///         the equivalent value of collateral plus a 5 % bonus.
    /// @param borrower   Address of the position to liquidate
    /// @param debtAmount Amount of debt the liquidator wishes to repay (capped at full debt)
    function liquidate(address borrower, uint256 debtAmount) external nonReentrant {
        if (debtAmount == 0) revert ZeroAmount();
        _accrueInterest(borrower);

        uint256 hf = _healthFactor(borrower);
        if (hf >= PRECISION) revert PositionHealthy(hf);

        Position storage pos = positions[borrower];
        uint256 repayAmount = debtAmount > pos.debt ? pos.debt : debtAmount;

        // Calculate collateral to seize = debt repaid (in collateral units) * (1 + bonus%).
        uint256 debtInUsd = _usdValue(repayAmount, _getPrice(BORROW_FEED));
        uint256 collateralPrice = _getPrice(COLLATERAL_FEED);
        // collateralToSeize = debtInUsd * (100 + bonus) / (100 * collateralPrice) * 1e8
        uint256 collateralToSeize = (debtInUsd * (100 + LIQUIDATION_BONUS) * 1e8) / (100 * collateralPrice);
        if (collateralToSeize > pos.collateral) collateralToSeize = pos.collateral;

        // State updates before external calls (CEI pattern).
        pos.debt -= repayAmount;
        // Cap debtPrincipal so it never exceeds the remaining debt after partial liquidation.
        if (pos.debtPrincipal > pos.debt) pos.debtPrincipal = pos.debt;

        pos.collateral -= collateralToSeize;
        totalDebt -= repayAmount;
        totalCollateral -= collateralToSeize;
        totalAvailableLiquidity += repayAmount;

        BORROW_TOKEN.safeTransferFrom(msg.sender, address(this), repayAmount);
        COLLATERAL_TOKEN.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(msg.sender, borrower, repayAmount, collateralToSeize);
    }

    // ─── View helpers ────────────────────────────────────────────────────────

    /// @notice Returns the health factor for `user` (PRECISION = 1.0, < PRECISION = liquidatable).
    function healthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /// @notice Returns the maximum additional amount `user` can borrow right now.
    function maxBorrow(address user) external view returns (uint256) {
        Position memory pos = positions[user];
        uint256 max = _maxBorrow(user);
        return max > pos.debt ? max - pos.debt : 0;
    }

    /// @notice Preview the accrued interest for `user` up to the current block.
    function pendingInterest(address user) external view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.debt == 0 || pos.lastAccrualTime == 0) return 0;
        uint256 elapsed = block.timestamp - pos.lastAccrualTime;
        return (pos.debt * INTEREST_RATE_PER_SECOND * elapsed) / 1e18;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @dev Accrues linear interest on `user`'s debt since `lastAccrualTime`.
    function _accrueInterest(address user) internal {
        Position storage pos = positions[user];
        if (pos.debt == 0 || pos.lastAccrualTime == 0) {
            pos.lastAccrualTime = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - pos.lastAccrualTime;
        if (elapsed == 0) return;

        uint256 interest = (pos.debt * INTEREST_RATE_PER_SECOND * elapsed) / 1e18;
        pos.debt += interest;
        totalDebt += interest;
        pos.lastAccrualTime = block.timestamp;

        emit InterestAccrued(user, interest, pos.debt);
    }

    /// @dev health factor = (collateral_USD * LIQUIDATION_THRESHOLD%) / debt_USD, scaled by PRECISION.
    function _healthFactor(address user) internal view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.debt == 0) return type(uint256).max;

        uint256 collateralUsd = _usdValue(pos.collateral, _getPrice(COLLATERAL_FEED));
        uint256 debtUsd = _usdValue(pos.debt, _getPrice(BORROW_FEED));
        uint256 adjustedCollateral = (collateralUsd * LIQUIDATION_THRESHOLD) / 100;
        return (adjustedCollateral * PRECISION) / debtUsd;
    }

    /// @dev max borrow = collateral_USD * LTV% expressed in borrowToken units.
    function _maxBorrow(address user) internal view returns (uint256) {
        Position memory pos = positions[user];
        uint256 collateralUsd = _usdValue(pos.collateral, _getPrice(COLLATERAL_FEED));
        uint256 maxBorrowUsd = (collateralUsd * LTV_RATIO) / 100;
        uint256 borrowPrice = _getPrice(BORROW_FEED);
        // Convert USD value back to borrow-token units (both have 18 dec, price has 8 dec).
        return (maxBorrowUsd * 1e8) / borrowPrice;
    }

    /// @dev Converts a token amount (18 dec) to USD value (18 dec) using an 8-dec Chainlink price.
    function _usdValue(uint256 amount, uint256 price8dec) internal pure returns (uint256) {
        return (amount * price8dec) / 1e8;
    }

    /// @dev Fetches and validates the latest price from a Chainlink aggregator.
    function _getPrice(AggregatorV3Interface feed) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice(answer);
        if (block.timestamp - updatedAt > PRICE_STALENESS_WINDOW) {
            revert StalePrice(updatedAt, block.timestamp);
        }
        // answer > 0 is checked above, so truncation to uint256 is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }
}

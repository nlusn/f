// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LPToken} from "./LPToken.sol";

/// @title AMM
/// @notice Constant-product automated market maker implementing x*y=k with a 0.3% swap fee.
/// @dev    Closely follows the Uniswap V2 design.  Key properties:
///         - MINIMUM_LIQUIDITY (1000) is permanently burned on the first deposit to prevent
///           first-depositor inflation attacks.
///         - The 0.3% fee stays in the pool, gradually increasing k and rewarding LP holders.
///         - All external state-changing functions are protected by ReentrancyGuard.
///         - SafeERC20 is used for every token interaction.
contract AMM is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────────────────

    /// @dev Numerator for the post-fee input amount (997/1000 → 0.3% fee retained).
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    /// @dev Burned to address(1) on first mint so totalSupply can never reach 0 again.
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;

    // ─── Immutables ──────────────────────────────────────────────────────────

    // solhint-disable var-name-mixedcase
    IERC20  public immutable TOKEN_A;
    IERC20  public immutable TOKEN_B;
    LPToken public immutable LP_TOKEN;
    // solhint-enable var-name-mixedcase

    // ─── State ───────────────────────────────────────────────────────────────

    uint256 public reserveA;
    uint256 public reserveB;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error ZeroAmount();
    error InsufficientLiquidity();
    error InsufficientLiquidityMinted();
    error SlippageExceeded(uint256 received, uint256 minimum);
    error InvalidToken(address token);
    error DeadlineExpired(uint256 deadline, uint256 current);

    // ─── Events ──────────────────────────────────────────────────────────────

    /// @notice Emitted whenever liquidity is added to the pool.
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);

    /// @notice Emitted whenever liquidity is removed from the pool.
    event LiquidityRemoved(address indexed provider, uint256 lpBurned, uint256 amountA, uint256 amountB);

    /// @notice Emitted on every successful swap.
    event Swapped(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut
    );

    /// @notice Emitted after every reserve update (including swaps and liquidity changes).
    event ReservesUpdated(uint256 newReserveA, uint256 newReserveB);

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param _tokenA Address of the first token in the pair
    /// @param _tokenB Address of the second token in the pair
    constructor(address _tokenA, address _tokenB) {
        TOKEN_A   = IERC20(_tokenA);
        TOKEN_B   = IERC20(_tokenB);
        // The AMM itself is granted MINTER_ROLE inside LPToken's constructor.
        LP_TOKEN  = new LPToken("AMM LP Token", "ALP", address(this));
    }

    // ─── Liquidity ───────────────────────────────────────────────────────────

    /// @notice Adds liquidity to the pool and mints LP tokens.
    /// @dev    On the very first deposit, the amounts set the price.  On subsequent deposits
    ///         the optimal amounts are calculated to maintain the current ratio.
    /// @param amountADesired Maximum token A the caller is willing to deposit
    /// @param amountBDesired Maximum token B the caller is willing to deposit
    /// @param amountAMin     Minimum token A accepted (slippage guard)
    /// @param amountBMin     Minimum token B accepted (slippage guard)
    /// @param to             Recipient of the LP tokens
    /// @param deadline       Unix timestamp after which the transaction reverts
    /// @return amountA   Actual token A deposited
    /// @return amountB   Actual token B deposited
    /// @return liquidity LP tokens minted
    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (amountADesired == 0 || amountBDesired == 0) revert ZeroAmount();

        (amountA, amountB) = _optimalAmounts(amountADesired, amountBDesired, amountAMin, amountBMin);

        TOKEN_A.safeTransferFrom(msg.sender, address(this), amountA);
        TOKEN_B.safeTransferFrom(msg.sender, address(this), amountB);

        liquidity = _mintLp(to, amountA, amountB);

        _updateReserves(reserveA + amountA, reserveB + amountB);
        emit LiquidityAdded(to, amountA, amountB, liquidity);
    }

    /// @notice Burns LP tokens and returns the proportional share of pool reserves.
    /// @param lpAmount   Amount of LP tokens to burn
    /// @param amountAMin Minimum token A to receive (slippage guard)
    /// @param amountBMin Minimum token B to receive (slippage guard)
    /// @param to         Recipient of the returned tokens
    /// @param deadline   Unix timestamp after which the transaction reverts
    /// @return amountA Token A returned
    /// @return amountB Token B returned
    function removeLiquidity(
        uint256 lpAmount,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (lpAmount == 0) revert ZeroAmount();

        uint256 totalSupply = LP_TOKEN.totalSupply();
        amountA = (lpAmount * reserveA) / totalSupply;
        amountB = (lpAmount * reserveB) / totalSupply;

        if (amountA < amountAMin) revert SlippageExceeded(amountA, amountAMin);
        if (amountB < amountBMin) revert SlippageExceeded(amountB, amountBMin);

        // Burn first, then transfer (Checks-Effects-Interactions).
        LP_TOKEN.burn(msg.sender, lpAmount);
        _updateReserves(reserveA - amountA, reserveB - amountB);

        TOKEN_A.safeTransfer(to, amountA);
        TOKEN_B.safeTransfer(to, amountB);

        emit LiquidityRemoved(to, lpAmount, amountA, amountB);
    }

    // ─── Swap ────────────────────────────────────────────────────────────────

    /// @notice Swaps an exact amount of `tokenIn` for as many `tokenOut` as possible.
    /// @param tokenIn      Address of the input token (must be TOKEN_A or TOKEN_B)
    /// @param amountIn     Exact input amount
    /// @param amountOutMin Minimum output required (slippage guard)
    /// @param to           Recipient of output tokens
    /// @param deadline     Unix timestamp after which the transaction reverts
    /// @return amountOut Actual output amount received
    function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address to, uint256 deadline)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (amountIn == 0) revert ZeroAmount();

        bool isAtoB = tokenIn == address(TOKEN_A);
        if (!isAtoB && tokenIn != address(TOKEN_B)) revert InvalidToken(tokenIn);

        (uint256 reserveIn, uint256 reserveOut, IERC20 tokenOut) =
            isAtoB ? (reserveA, reserveB, TOKEN_B) : (reserveB, reserveA, TOKEN_A);

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < amountOutMin) revert SlippageExceeded(amountOut, amountOutMin);

        // Pull input before pushing output (Checks-Effects-Interactions).
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        tokenOut.safeTransfer(to, amountOut);

        _updateReserves(
            isAtoB ? reserveA + amountIn : reserveA - amountOut,
            isAtoB ? reserveB - amountOut : reserveB + amountIn
        );

        emit Swapped(msg.sender, tokenIn, amountIn, address(tokenOut), amountOut);
    }

    // ─── View ────────────────────────────────────────────────────────────────

    /// @notice Returns the expected output for a given input without executing a swap.
    /// @param tokenIn  Input token address
    /// @param amountIn Input amount
    /// @return amountOut Expected output (after 0.3% fee)
    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        bool isAtoB = tokenIn == address(TOKEN_A);
        if (!isAtoB && tokenIn != address(TOKEN_B)) revert InvalidToken(tokenIn);
        (uint256 reserveIn, uint256 reserveOut) = isAtoB ? (reserveA, reserveB) : (reserveB, reserveA);
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @notice Returns spot prices scaled by 1e18.
    /// @return priceAinB How many TOKEN_B units per 1e18 TOKEN_A
    /// @return priceBinA How many TOKEN_A units per 1e18 TOKEN_B
    function getSpotPrice() external view returns (uint256 priceAinB, uint256 priceBinA) {
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        priceAinB = (reserveB * 1e18) / reserveA;
        priceBinA = (reserveA * 1e18) / reserveB;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @dev Applies the constant-product formula with a 0.3% fee.
    ///      amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator       = amountInWithFee * reserveOut;
        uint256 denominator     = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        return numerator / denominator;
    }

    /// @dev Computes the optimal deposit amounts that preserve the current pool ratio.
    function _optimalAmounts(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        // Empty pool — caller sets the initial price.
        if (reserveA == 0 && reserveB == 0) return (amountADesired, amountBDesired);

        uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
        if (amountBOptimal <= amountBDesired) {
            if (amountBOptimal < amountBMin) revert SlippageExceeded(amountBOptimal, amountBMin);
            return (amountADesired, amountBOptimal);
        }

        uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
        if (amountAOptimal < amountAMin) revert SlippageExceeded(amountAOptimal, amountAMin);
        return (amountAOptimal, amountBDesired);
    }

    /// @dev Calculates and mints LP tokens for a new deposit.
    function _mintLp(address to, uint256 amountA, uint256 amountB) internal returns (uint256 liquidity) {
        uint256 totalSupply = LP_TOKEN.totalSupply();

        if (totalSupply == 0) {
            // Geometric mean minus the permanently-locked minimum.
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            LP_TOKEN.mint(address(1), MINIMUM_LIQUIDITY); // lock forever
        } else {
            // Proportional to the smaller of the two deposit ratios.
            liquidity = Math.min((amountA * totalSupply) / reserveA, (amountB * totalSupply) / reserveB);
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();
        LP_TOKEN.mint(to, liquidity);
    }

    /// @dev Updates stored reserves and emits ReservesUpdated.
    function _updateReserves(uint256 newReserveA, uint256 newReserveB) internal {
        reserveA = newReserveA;
        reserveB = newReserveB;
        emit ReservesUpdated(newReserveA, newReserveB);
    }
}

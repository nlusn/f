// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ChainlinkPriceOracle
/// @notice A reusable price-feed wrapper that validates Chainlink data for staleness and correctness.
///
/// @dev    Usage pattern:
///         1. Deploy with a default staleness threshold.
///         2. Register feeds via `setFeed(token, aggregator)`.
///         3. Call `getPrice(token)` to get the latest validated price.
///
///         Staleness check: reverts if the price is older than `maxStaleness` seconds.
///         Price validation: reverts if the price is zero or negative.
contract ChainlinkPriceOracle is AccessControl {
    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    // ─── State ───────────────────────────────────────────────────────────────

    /// @notice Maximum age (seconds) of a Chainlink round before it is treated as stale.
    uint256 public maxStaleness;

    /// @notice Mapping from token address to its Chainlink price feed.
    mapping(address => AggregatorV3Interface) public feeds;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error FeedNotSet(address token);
    error StalePrice(address token, uint256 updatedAt, uint256 currentTime);
    error InvalidPrice(address token, int256 price);
    error ZeroAddress();
    error ZeroStaleness();

    // ─── Events ──────────────────────────────────────────────────────────────

    event FeedUpdated(address indexed token, address indexed feed);
    event MaxStalenessUpdated(uint256 oldValue, uint256 newValue);

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param admin           Initial admin
    /// @param _maxStaleness   Default staleness threshold in seconds (e.g., 3600 for 1 hour)
    constructor(address admin, uint256 _maxStaleness) {
        if (admin == address(0)) revert ZeroAddress();
        if (_maxStaleness == 0) revert ZeroStaleness();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN_ROLE, admin);
        maxStaleness = _maxStaleness;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    /// @notice Sets or updates the Chainlink feed for a given token.
    /// @param token Token address
    /// @param feed  Chainlink AggregatorV3Interface address
    function setFeed(address token, address feed) external onlyRole(ORACLE_ADMIN_ROLE) {
        if (token == address(0) || feed == address(0)) revert ZeroAddress();
        feeds[token] = AggregatorV3Interface(feed);
        emit FeedUpdated(token, feed);
    }

    /// @notice Updates the staleness threshold.
    /// @param _maxStaleness New threshold in seconds
    function setMaxStaleness(uint256 _maxStaleness) external onlyRole(ORACLE_ADMIN_ROLE) {
        if (_maxStaleness == 0) revert ZeroStaleness();
        emit MaxStalenessUpdated(maxStaleness, _maxStaleness);
        maxStaleness = _maxStaleness;
    }

    // ─── Price queries ───────────────────────────────────────────────────────

    /// @notice Returns the latest validated price for `token` (in feed decimals).
    /// @param token Token address to query
    /// @return price The latest price (always positive)
    function getPrice(address token) external view returns (uint256 price) {
        AggregatorV3Interface feed = feeds[token];
        if (address(feed) == address(0)) revert FeedNotSet(token);

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice(token, answer);
        if (block.timestamp - updatedAt > maxStaleness) {
            revert StalePrice(token, updatedAt, block.timestamp);
        }

        return uint256(answer);
    }

    /// @notice Returns the latest validated price along with feed decimals.
    /// @param token Token address to query
    /// @return price    The latest price
    /// @return decimals Feed decimals
    function getPriceWithDecimals(address token) external view returns (uint256 price, uint8 decimals) {
        AggregatorV3Interface feed = feeds[token];
        if (address(feed) == address(0)) revert FeedNotSet(token);

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice(token, answer);
        if (block.timestamp - updatedAt > maxStaleness) {
            revert StalePrice(token, updatedAt, block.timestamp);
        }

        return (uint256(answer), feed.decimals());
    }

    /// @notice Returns the latest validated price normalized to 18 decimals.
    /// @param token Token address to query
    /// @return price The latest price scaled to 18 decimals
    function getPriceNormalized(address token) external view returns (uint256 price) {
        AggregatorV3Interface feed = feeds[token];
        if (address(feed) == address(0)) revert FeedNotSet(token);

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice(token, answer);
        if (block.timestamp - updatedAt > maxStaleness) {
            revert StalePrice(token, updatedAt, block.timestamp);
        }

        uint8 feedDecimals = feed.decimals();
        if (feedDecimals < 18) {
            return uint256(answer) * 10 ** (18 - feedDecimals);
        } else if (feedDecimals > 18) {
            return uint256(answer) / 10 ** (feedDecimals - 18);
        }
        return uint256(answer);
    }
}

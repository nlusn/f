// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title MockV3Aggregator
/// @notice Full-featured Chainlink V3 Aggregator mock for testing.
///
/// @dev    Allows test scripts to:
///         - Set an initial price and decimals.
///         - Update the price via `updateAnswer`.
///         - Manually set the `updatedAt` timestamp for staleness testing.
///         - Access a round counter that increments on each price update.
contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;
    uint256 private _startedAt;

    /// @param decimals_ Number of decimals for the price feed (typically 8)
    /// @param initialAnswer Initial price answer
    constructor(uint8 decimals_, int256 initialAnswer) {
        _decimals = decimals_;
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
        _startedAt = block.timestamp;
        _roundId = 1;
    }

    /// @notice Updates the price and increments the round.
    /// @param answer New price answer
    function updateAnswer(int256 answer) external {
        _answer = answer;
        _updatedAt = block.timestamp;
        _startedAt = block.timestamp;
        _roundId++;
    }

    /// @notice Manually sets the updatedAt timestamp (for staleness tests).
    /// @param updatedAt New updatedAt timestamp
    function setUpdatedAt(uint256 updatedAt) external {
        _updatedAt = updatedAt;
    }

    /// @notice Manually sets the round ID.
    /// @param roundId New round ID
    function setRoundId(uint80 roundId) external {
        _roundId = roundId;
    }

    /// @inheritdoc AggregatorV3Interface
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _startedAt, _updatedAt, _roundId);
    }
}

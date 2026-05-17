// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

/// @notice Configurable mock Chainlink aggregator for unit tests.
contract MockAggregator is AggregatorV3Interface {
    int256 private _answer;
    uint8 private _decimals;
    uint256 private _updatedAt;

    constructor(int256 initialPrice, uint8 decimals_) {
        _answer = initialPrice;
        _decimals = decimals_;
        _updatedAt = block.timestamp;
    }

    function setPrice(int256 price) external {
        _answer = price;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _answer, block.timestamp, _updatedAt, 1);
    }
}

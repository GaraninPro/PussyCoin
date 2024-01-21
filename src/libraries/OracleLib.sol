// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60   = 10800

    function staleChecklatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 staleCheck = block.timestamp - updatedAt;

        if (staleCheck > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getTimeOut(AggregatorV3Interface /* priceFeed */ ) public pure returns (uint256) {
        return TIMEOUT;
    }
}

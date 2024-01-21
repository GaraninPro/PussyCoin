// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator aggregator;

    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000 ether;

    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    function testGetTimeOut() public {
        uint256 expectedTimeOut = 3 hours;
        assertEq(expectedTimeOut, OracleLib.getTimeOut(AggregatorV3Interface(address(aggregator))));
    }

    function testRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);

        vm.roll(block.number + 1);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);

        AggregatorV3Interface(address(aggregator)).staleChecklatestRoundData();
    }

    function testRevertsOnBadData() public {
        uint80 roundId = 0;
        int256 answer = 0;
        uint256 timeStamp = 0;
        uint256 startedAt = 0;

        aggregator.updateRoundData(roundId, answer, timeStamp, startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);

        AggregatorV3Interface(address(aggregator)).staleChecklatestRoundData();
    }
}

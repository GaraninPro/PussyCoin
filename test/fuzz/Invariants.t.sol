//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployPs} from "../../script/DeployPs.s.sol";
import {PSengine} from "../../src/PSengine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    StableCoin stableCoin;
    PSengine engine;
    HelperConfig config;
    Handler handler;
    ////////////////////
    address ethUsdPriceFeed;
    address btcPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    /////////////////////////////////////

    function setUp() public {
        DeployPs deployer = new DeployPs();

        (stableCoin, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        //targetContract(address(stableCoin));
        handler = new Handler(engine, stableCoin);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalCoinSupply() public view {
        uint256 totalsupply = stableCoin.totalSupply();

        uint256 totalWethDep = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDep = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethvalue = engine.getUsdValue(weth, totalWethDep);

        uint256 wbtcvalue = engine.getUsdValue(wbtc, totalWbtcDep);
        console.log("wethValue:", wethvalue);
        console.log("wbtcValue:", wbtcvalue);
        console.log("Total Supply:", totalsupply);
        console.log("TimesMintCalled:", handler.timesMintCalled());
        assert(wethvalue + wbtcvalue >= totalsupply);
    }

    function invariant_getterFunctionsShouldNotRevert() public view {
        engine.getPs();
        engine.getPrecision();
        engine.getLiquidationPrecision();
        engine.getAdditionalFeedPrecision();
        engine.getCollateralTokens();
        engine.getLiquidationBonus();
        engine.getLiquidationPrecision();
        engine.getLiquidationThreshold();
        engine.getMinHealthFactor();
        engine.getAdditionalFeedPrecision();
    }
}

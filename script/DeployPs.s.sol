// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {PSengine} from "../src/PSengine.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPs is Script {

    address[] public tokenAddresses;
        address[] public priceFeedAddresses;
    function run() external returns (StableCoin, PSengine, HelperConfig) {
        

        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        StableCoin stableCoin = new StableCoin();
        PSengine engine = new PSengine(tokenAddresses, priceFeedAddresses, address(stableCoin));
        stableCoin.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (stableCoin, engine, config);
    }
}

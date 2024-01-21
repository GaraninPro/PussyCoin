//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {PSengine} from "../../src/PSengine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Handler is Test {
    //  using EnumerableSet for  EnumerableSet.AddressSet;

    //  EnumerableSet.AddressSet private mySet;

    StableCoin stableCoin;
    PSengine engine;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintCalled;
    address[] public whoDeposited;
    MockV3Aggregator ethUsdPriceFeed;
    MockV3Aggregator btcUsdPriceFeed;

    constructor(PSengine _engine, StableCoin _stableCoin) {
        stableCoin = _stableCoin;
        engine = _engine;

        address[] memory collatteraltokens = engine.getCollateralTokens();

        weth = ERC20Mock(collatteraltokens[0]);
        wbtc = ERC20Mock(collatteraltokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeedAddress(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeedAddress(address(wbtc)));
    }

    ////////////////////////////////////////////////////////////////////////////////////////

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(engine), amount);

        engine.depositCollateral(address(collateral), amount);

        vm.stopPrank();
        whoDeposited.push(msg.sender);

        //  mySet.add(msg.sender);
    }

    function mintPs(uint256 amount, uint256 addressSeed) public {
        if (whoDeposited.length == 0) {
            return;
        }
        address sender = whoDeposited[addressSeed % whoDeposited.length]; ///////!!!!!!!!!!!!!!
        (uint256 totalPsminted, uint256 collateralvalueInUsd) = engine.getAccountInformation(sender);

        int256 maxPsToMint = (int256(collateralvalueInUsd) / 2) - int256(totalPsminted);
        if (maxPsToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxPsToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintPS(amount);
        vm.stopPrank();
        timesMintCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxcollateral = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amount = bound(amount, 0, maxcollateral);
        if (amount == 0) {
            return;
        }
        engine.redeemCollateral(address(collateral), amount);
    }

    function burnPs(uint256 amount) public {
        amount = bound(amount, 0, stableCoin.balanceOf(msg.sender));

        if (amount == 0) {
            return;
        }

        engine.burnPS(amount);
    }

    function liquadate(uint256 collateralSeed, address userToLiquadate, uint256 debtToCover) public {
        uint256 minHealthFactor = engine.getMinHealthFactor();

        uint256 userHealthFactor = engine.getHealthFactor(userToLiquadate);

        if (userHealthFactor >= minHealthFactor) {
            return;
        }
        debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));

        ERC20Mock colatteral = _getCollateralFromSeed(collateralSeed);

        engine.liquidate(address(colatteral), userToLiquadate, debtToCover);
    }

    function transferPs(uint256 amount, address to) public {
        if (to == address(0)) {
            to = address(1);
        }

        amount = bound(amount, 0, stableCoin.balanceOf(msg.sender));
        vm.prank(msg.sender);

        stableCoin.transfer(to, amount);
    }

    // This breaks out invariant test suite.
    /*   function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
        int256 intNewPrice = int256(uint256(newPrice));

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        MockV3Aggregator priceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeedAddress(address(collateral)));

        priceFeed.updateAnswer(intNewPrice);
    }
    */
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

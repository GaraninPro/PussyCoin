// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {StdCheats} from "forge-std/StdCheats.sol";
import {Test, console} from "forge-std/Test.sol";
import {DeployPs} from "../../script/DeployPs.s.sol";
import {PSengine} from "../../src/PSengine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
///////////////////////////////////////////////////////////////////////
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedMintPs} from "../mocks/MockFailedMintPs.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtPs} from "../mocks/MockMoreDebtPs.sol";

contract PSengineTest is Test {
    StableCoin stableCoin;
    PSengine engine;
    HelperConfig config;
    ////////////////////
    address ethUsdPriceFeed;
    address btcPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    /////////////////////////////////////
    address public user = address(1);
    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100 ether;
    //////////////////////////////////////////////////////////
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    ///////////////////////////////////////////////////////////////////////
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;
    ////////////////////////////////////////////

    event collateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address collateralToken, uint256 amount
    );
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public {
        DeployPs deployer = new DeployPs();

        (stableCoin, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        // Should we put our integration tests here?
        else {
            user = vm.addr(deployerKey);
            ERC20Mock mockErc = new ERC20Mock("MOCK", "MOCK", user, 100e18);
            MockV3Aggregator aggregatorMock = new MockV3Aggregator(config.DECIMALS(), config.ETH_USD_PRICE());
            vm.etch(weth, address(mockErc).code);
            vm.etch(wbtc, address(mockErc).code);
            vm.etch(ethUsdPriceFeed, address(aggregatorMock).code);
            vm.etch(btcPriceFeed, address(aggregatorMock).code);
        }

        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    /////////////////
    ///  Constructor Tests //
    //////////
    address[] priceFeeds;
    address[] tokenAddresses;

    function testRevertsIfTokenlengthNotMatchPriceFeeds() public {
        priceFeeds.push(ethUsdPriceFeed);
        priceFeeds.push(btcPriceFeed);
        tokenAddresses.push(weth);

        vm.expectRevert(PSengine.PSengine_TokenAddressesAndPricefeedAddressesLengthMustBeEqual.selector);

        new PSengine(tokenAddresses, priceFeeds, address(stableCoin));
    }

    /////////////////
    //// Price Tests///
    ////////////////
    modifier depCollateral() {
        vm.startPrank(user);

        ERC20Mock(weth).approve(address(engine), amountCollateral);

        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();

        _;
    }

    function testGetUsdValueOfCrypto() public view {
        uint256 ethAmount = 1e18;

        uint256 expectedValue = 2000e18;

        uint256 actualValue = engine.getUsdValue(weth, ethAmount);
        console.log(actualValue);
        assert(expectedValue == actualValue);
    }

    function testGetTokenFromUsd() public {
        uint256 usdAmount = 100e18;

        uint256 expectedWeth = 5e16;

        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        console.log(actualWeth);
        assertEq(expectedWeth, actualWeth);
    }

    function testAccountCollateralValue() public depCollateral {
        uint256 expectedValue = 20000e18;
        uint256 actualValue = engine.getAccountCollateralValue(user);

        assertEq(expectedValue, actualValue);
    }

    ///////////////////////
    /// depositCollateral Tests
    //////////////////////

    function testRevertsIfTransferFromFailed() public {
        address owner = msg.sender;

        vm.startPrank(owner);

        MockFailedTransferFrom mockCoin = new MockFailedTransferFrom();

        tokenAddresses = [address(mockCoin)];
        priceFeeds = [ethUsdPriceFeed];

        PSengine mockEngine = new PSengine(tokenAddresses, priceFeeds, address(mockCoin));

        mockCoin.mint(user, amountCollateral);

        mockCoin.transferOwnership(address(mockEngine));

        vm.stopPrank();

        vm.startPrank(user);

        ERC20Mock(address(mockCoin)).approve(address(mockEngine), amountCollateral);

        vm.expectRevert(PSengine.PSengine_TransferFailed.selector);

        mockEngine.depositCollateral(address(mockCoin), amountCollateral);

        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        vm.expectRevert(PSengine.PSengine_NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedToken() public {
        ERC20Mock ranToken = new ERC20Mock("ran", "ran", user, 100e18);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(PSengine.PSengine_TokenNotAllowed.selector, address(ranToken)));

        engine.depositCollateral(address(ranToken), amountCollateral);

        vm.stopPrank();
    }

    function testCanDepositCollateralAndHaveAccountInfo() public depCollateral {
        (uint256 totalPsMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);

        uint256 expectedPsMinted = 0;
        uint256 expectedCollateralInWeth = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalPsMinted, expectedPsMinted);
        assertEq(amountCollateral, expectedCollateralInWeth);
    }

    function testCanDepositCollateralWithoutMinting() public depCollateral {
        uint256 expectedBalance = stableCoin.balanceOf(user);

        assertEq(expectedBalance, 0);
    }
    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    /////////////////////////////////////

    modifier depositedCollateralAndMintedPs() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        engine.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);

        vm.stopPrank();

        _;
    }

    function testRevertsIfMintedCoinsBreakHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();

        amountToMint =
            (amountCollateral * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();

        vm.startPrank(user);

        ERC20Mock(weth).approve(address(engine), amountCollateral);

        uint256 expectedFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, amountCollateral));
        console.log(expectedFactor);
        console.log(amountToMint);
        vm.expectRevert(abi.encodeWithSelector(PSengine.PSengine_BreaksHealthFactor.selector, expectedFactor));

        engine.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);

        vm.stopPrank();
    }

    function testCanMintWithDepositedPs() public depositedCollateralAndMintedPs {
        uint256 userbalance = stableCoin.balanceOf(user);
        console.log(userbalance);
        assertEq(amountToMint, userbalance);
    }

    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////
    function testRevertsIfMintFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedMintPs mockDsc = new MockFailedMintPs();
        tokenAddresses = [weth];
        priceFeeds = [ethUsdPriceFeed];
        // address owner = msg.sender;
        vm.prank(owner);
        PSengine mockDsce = new PSengine(tokenAddresses, priceFeeds, address(mockDsc));
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce), amountCollateral);

        vm.expectRevert(PSengine.PSengine_MintFailed.selector);
        mockDsce.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }
    /*
    function testRevertsIfMintFails2() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedMintPs mockCoin = new MockFailedMintPs();

        tokenAddresses = [address(mockCoin)];
        priceFeeds = [ethUsdPriceFeed];
        vm.prank(owner);
        PSengine mockEngine = new PSengine(tokenAddresses, priceFeeds, address(mockCoin));
        vm.prank(owner);
        mockCoin.mint(user, amountCollateral);
        vm.prank(owner);
        mockCoin.transferOwnership(address(mockEngine));

        vm.startPrank(user);

        ERC20Mock(address(mockCoin)).approve(address(mockEngine), amountCollateral);

        vm.expectRevert(PSengine.PSengine_MintFailed.selector);

        mockEngine.depositCollateralAndMintPDS(address(mockEngine), amountCollateral, amountToMint);

        vm.stopPrank();
    }
    */

    function testRevertsIfMintAmountZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);
        vm.expectRevert(PSengine.PSengine_NeedsMoreThanZero.selector);

        engine.mintPS(0);
        vm.stopPrank();
    }

    function testRevertsIfBreakHealthFactor() public depCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();

        amountToMint =
            (amountCollateral * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();

        vm.startPrank(user);
        uint256 healthfactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, amountCollateral));

        vm.expectRevert(abi.encodeWithSelector(PSengine.PSengine_BreaksHealthFactor.selector, healthfactor));

        engine.mintPS(amountToMint);

        vm.stopPrank();
    }

    function testCanMintPs() public depCollateral {
        vm.prank(user);
        engine.mintPS(amountToMint);

        uint256 balance = stableCoin.balanceOf(user);

        assertEq(amountToMint, balance);
    }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    function testRevertsIfBurnAmountZero() public {
        vm.startPrank(user);

        ERC20Mock(weth).approve(address(engine), amountCollateral);

        engine.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);

        vm.expectRevert(PSengine.PSengine_NeedsMoreThanZero.selector);
        engine.burnPS(0);
        vm.stopPrank();
    }

    function testCantburnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        engine.burnPS(1000);
    }

    function testCanBurnPs() public depositedCollateralAndMintedPs {
        vm.startPrank(user);

        stableCoin.approve(address(engine), amountToMint);

        engine.burnPS(amountToMint);
        vm.stopPrank();
        uint256 balance = stableCoin.balanceOf(user);

        assertEq(balance, 0);
    }
    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    function testReversIfTransferFailed() public {
        address owner = msg.sender;

        vm.startPrank(owner);

        MockFailedTransfer mockCoin = new MockFailedTransfer();

        tokenAddresses = [address(mockCoin)];
        priceFeeds = [ethUsdPriceFeed];

        PSengine mockEngine = new PSengine(tokenAddresses, priceFeeds, address(mockCoin));

        mockCoin.mint(user, amountCollateral);

        mockCoin.transferOwnership(address(mockEngine));

        vm.stopPrank();

        vm.startPrank(user);

        ERC20Mock(address(mockCoin)).approve(address(mockEngine), amountCollateral);

        mockEngine.depositCollateral(address(mockCoin), amountCollateral);

        vm.expectRevert(PSengine.PSengine_TransferFailed.selector);

        mockEngine.redeemCollateral(address(mockCoin), amountCollateral);

        vm.stopPrank();
    }

    function testRevertsIfRedeemIsZero() public {
        vm.startPrank(user);

        ERC20Mock(weth).approve(address(engine), amountCollateral);

        engine.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);
        vm.expectRevert(PSengine.PSengine_NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);

        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depCollateral {
        vm.startPrank(user);

        engine.redeemCollateral(weth, amountCollateral);

        uint256 balance = ERC20Mock(weth).balanceOf(user);

        assertEq(amountCollateral, balance);
        vm.stopPrank();
    }

    function testCollateralRedeemedWithCorrectArgs() public depCollateral {
        vm.expectEmit(true, true, true, true, address(engine));

        emit collateralRedeemed(user, user, weth, amountCollateral);

        vm.startPrank(user);
        engine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }
    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testRedeemMustBeMoreThanZeroWhenRedeemForPs() public depositedCollateralAndMintedPs {
        vm.startPrank(user);

        stableCoin.approve(address(engine), amountToMint);
        vm.expectRevert(PSengine.PSengine_NeedsMoreThanZero.selector);
        engine.redeemCollateralForPS(weth, 0, amountToMint);

        vm.stopPrank();
    }

    function testCanRedeemCollateralForPs() public depositedCollateralAndMintedPs {
        vm.startPrank(user);

        stableCoin.approve(address(engine), amountToMint);
        engine.redeemCollateralForPS(weth, amountCollateral, amountToMint);

        vm.stopPrank();

        uint256 balance = stableCoin.balanceOf(user);

        assertEq(balance, 0);
    }
    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedPs {
        uint256 expectedHealthFactor = 100 ether;
        uint256 actualHealthFactor = engine.getHealthFactor(user);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedPs {
        int256 ethNewPrice = 18e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethNewPrice);

        uint256 userHealthFactor = engine.getHealthFactor(user);

        assertEq(userHealthFactor, 0.9 ether);
    }
    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        address owner = msg.sender;
        vm.startPrank(owner);

        MockMoreDebtPs mockDsc = new MockMoreDebtPs(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeeds = [ethUsdPriceFeed];

        PSengine mockDsce = new PSengine(tokenAddresses, priceFeeds, address(mockDsc));

        mockDsc.transferOwnership(address(mockDsce));
        vm.stopPrank();
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce), amountCollateral);

        mockDsce.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        collateralToCover = 1 ether;
        uint256 debtToCover = 10 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);

        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
        mockDsce.depositCollateralAndMintPDS(weth, collateralToCover, amountToMint);
        /// minted 100 coins

        mockDsc.approve(address(mockDsce), debtToCover); // request for 10 coins

        int256 ethUsdUpdatedPrice = 18e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.expectRevert(PSengine.PSengine_HealthFactorNotImproved.selector);

        mockDsce.liquidate(weth, user, debtToCover);

        vm.stopPrank();
    }

    function testCanNotLiquidateWithGoodHealthFactor() public depositedCollateralAndMintedPs {
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startPrank(liquidator);

        ERC20Mock(weth).approve(address(engine), collateralToCover);

        engine.depositCollateralAndMintPDS(weth, collateralToCover, amountToMint);

        stableCoin.approve(address(engine), amountToMint);

        vm.expectRevert(PSengine.PSengine_HealthFactorOk.selector);
        engine.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

    modifier terminated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintPDS(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        int256 ethNewPrice = 18e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethNewPrice);

        uint256 userHealthFactor = engine.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startPrank(liquidator);

        ERC20Mock(weth).approve(address(engine), collateralToCover);

        engine.depositCollateralAndMintPDS(weth, collateralToCover, amountToMint);

        stableCoin.approve(address(engine), amountToMint);

        engine.liquidate(weth, user, amountToMint);

        vm.stopPrank();

        _;
    }

    function testLiquidationPayOutCorrect() public terminated {
        uint256 liquidatorBalance = ERC20Mock(weth).balanceOf(liquidator);

        uint256 expectedLiquiBalance = engine.getTokenAmountFromUsd(weth, amountToMint)
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());

        console.log(liquidatorBalance);
        assertEq(liquidatorBalance, expectedLiquiBalance);
    }

    function testUserHasSomeCollateralAfterLiquidation() public terminated {
        uint256 amountLiquidatedfromUser = engine.getTokenAmountFromUsd(weth, amountToMint)
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());

        uint256 amountInUsdLiquidated = engine.getUsdValue(weth, amountLiquidatedfromUser);
        //////////////////////////////////////////////////////////////////////////////////
        uint256 expectedLeftAfterLiquidationInUsd = engine.getUsdValue(weth, amountCollateral) - amountInUsdLiquidated;

        uint256 actualCollateralValueOfUser = engine.getAccountCollateralValue(user);
        console.log(expectedLeftAfterLiquidationInUsd);
        assertEq(expectedLeftAfterLiquidationInUsd, actualCollateralValueOfUser);
    }

    function testUserHasNoMoreDebt() public terminated {
        (uint256 psMinted,) = engine.getAccountInformation(user);
        console.log(stableCoin.balanceOf(user));
        assertEq(psMinted, 0);
    }

    function testLiquidatorPaysUserDebt() public terminated {
        (uint256 psMinted,) = engine.getAccountInformation(liquidator);

        assertEq(psMinted, amountToMint);
        assertEq(stableCoin.balanceOf(liquidator), 0);
    }
    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////

    function testGetCollateralTokenPriceFeed() public {
        address pricefeed = engine.getCollateralTokenPriceFeedAddress(weth);
        assertEq(ethUsdPriceFeed, pricefeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = engine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testLiquidationThreshold() public {
        uint256 threshold = engine.getLiquidationThreshold();

        assertEq(threshold, LIQUIDATION_THRESHOLD);
    }

    function testAccountCollateralValueFromInformation() public depCollateral {
        (, uint256 collateralValue) = engine.getAccountInformation(user);

        uint256 expectedUsdValue = engine.getUsdValue(weth, amountCollateral);

        assertEq(collateralValue, expectedUsdValue);
    }

    function testCollateralBalanceOfUser() public depCollateral {
        uint256 collateralBalance = engine.getCollateralBalanceOfUser(user, weth);

        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public depCollateral {
        uint256 collateralValue = engine.getAccountCollateralValue(user);

        uint256 expectedvalue = engine.getUsdValue(weth, amountCollateral);

        assertEq(collateralValue, expectedvalue);
    }

    function testGetPs() public {
        address Ps = engine.getPs();
        assertEq(Ps, address(stableCoin));
    }

    function testGetLiquidationPrecision() public {
        uint256 expectedPrecision = 100;

        uint256 actualPrecision = engine.getLiquidationPrecision();

        assertEq(expectedPrecision, actualPrecision);
    }
}

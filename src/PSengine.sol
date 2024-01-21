// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {StableCoin} from "./StableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
//import {OracleLib} from "../../src/libraries/OracleLib.sol";

contract PSengine is ReentrancyGuard {
    ///////////////
    /// errors ///
    /////////////

    error PSengine_NeedsMoreThanZero();
    error PSengine_TokenAddressesAndPricefeedAddressesLengthMustBeEqual();
    error PSengine_TokenNotAllowed(address token);
    ////////////////////////////////////
    error PSengine_TransferFailed();
    error PSengine_MintFailed();
    ////////////////////////////////////////////
    error PSengine_BreaksHealthFactor(uint256 healthFactor);
    error PSengine_HealthFactorOk();
    error PSengine_HealthFactorNotImproved();
    ///////////////
    // Type//////
    ////////////

    //   using OracleLib for AggregatorV3Interface;

    //////////////
    //State Variables//
    ////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    /////////////////////////////////////////////////////////////getUsdValue
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200 percent overcollateralized
    ///your loan becomes eligible for liquidation when the value of your loan is equal to or more than 50% of your collateral.
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    /////////////////////////////////////////////////////_healthFactor
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address pricefeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 psMinted) private s_PsMinted;
    address[] private s_collateralTokens;
    StableCoin private immutable i_ps;
    //////////////
    //Events//
    ////////////

    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event collateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address collateralToken, uint256 amount
    );

    //////////////
    //modifiers//
    ////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert PSengine_NeedsMoreThanZero();
        }
        _;
    }

    modifier isAlowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert PSengine_TokenNotAllowed(token);
        }

        _;
    }

    //////////////
    //Functions//
    ////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address psAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert PSengine_TokenAddressesAndPricefeedAddressesLengthMustBeEqual();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_ps = StableCoin(psAddress);
    }

    /////////////
    //External Functions//
    ////////////
    function depositCollateralAndMintPDS(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintPS(amountToMint);
    }

    function redeemCollateralForPS(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountPS)
        external
        moreThanZero(amountCollateral)
    {
        _burnPs(amountPS, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthfactorBroken(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountOfCollateral)
        external
        moreThanZero(amountOfCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountOfCollateral, msg.sender, msg.sender);

        _revertIfHealthfactorBroken(msg.sender);
    }

    function burnPS(uint256 amount) external moreThanZero(amount) {
        _burnPs(amount, msg.sender, msg.sender);
        _revertIfHealthfactorBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover)
        /// In ETH or BTC
        external
        nonReentrant
        moreThanZero(debtToCover)
    {
        uint256 startingHealtfactor = _healthFactor(user);

        if (startingHealtfactor >= MIN_HEALTH_FACTOR) {
            revert PSengine_HealthFactorOk();
        }

        uint256 tokenAmountToCoverDebt = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 collateralBonus = (tokenAmountToCoverDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountToCoverDebt + collateralBonus;

        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnPs(debtToCover, user, msg.sender);

        uint256 finalHealthFactor = _healthFactor(user);
        if (finalHealthFactor <= startingHealtfactor) {
            revert PSengine_HealthFactorNotImproved();
        }
        _revertIfHealthfactorBroken(msg.sender);
    }

    ///////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////
    ///////////////    PUBLIC FUNCTIONS      ///////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        ///PUBLIC
        moreThanZero(amountCollateral)
        isAlowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit collateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert PSengine_TransferFailed();
        }
    }

    function mintPS(uint256 amountPsToMint) public nonReentrant moreThanZero(amountPsToMint) {
        s_PsMinted[msg.sender] += amountPsToMint; ////PUBLIC
        _revertIfHealthfactorBroken(msg.sender);
        bool minted = i_ps.mint(msg.sender, amountPsToMint); // PSengine  can call mint function in StableCoin
            // because ownership was transfered to it during Deploy
        if (!minted) {
            revert PSengine_MintFailed();
        }
    }

    /////////////
    //Private  Functions//
    ////////////

    function _burnPs(uint256 amountToBurn, address onBehalfOf, address psFrom) private {
        s_PsMinted[onBehalfOf] -= amountToBurn;

        bool success = i_ps.transferFrom(psFrom, address(this), amountToBurn);

        if (!success) revert PSengine_TransferFailed();

        i_ps.burn(amountToBurn);
    }

    function _redeemCollateral(address tokenCollateral, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateral] -= amountCollateral;

        emit collateralRedeemed(from, to, tokenCollateral, amountCollateral);

        bool success = IERC20(tokenCollateral).transfer(to, amountCollateral);

        if (!success) {
            revert PSengine_TransferFailed();
        }
    }

    //////////////////////////////////////////////////////////////////////////////
    ////////////////////  Private & Internal View & Pure Functions
    //////////////////////////////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalPsMinted, uint256 collateralValueUsd)
    {
        totalPsMinted = s_PsMinted[user];
        collateralValueUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalPsMinted, uint256 collateralValueUsd) = _getAccountInformation(user);
        //  return (collateralValueUsd / totalPsMinted);

        return _calculateHealthFactor(totalPsMinted, collateralValueUsd);
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 price,,,) = pricefeed.latestRoundData();

        return ((uint256(price) * amount) * ADDITIONAL_FEED_PRECISION) / PRECISION;
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        /// INTERNAL
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthfactorBroken(address user) internal view {
        ///INTERNAL
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) revert PSengine_BreaksHealthFactor(userHealthFactor);
    }

    //////////////////////////////////////
    //Public and External View Pure Functions//
    //////////////////////////////////////

    function calculateHealthFactor(uint256 totalPsMinted, uint256 collateralInUsd) external pure returns (uint256) {
        return _calculateHealthFactor(totalPsMinted, collateralInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalPsminted, uint256 collateralValueUsd)
    {
        (totalPsminted, collateralValueUsd) = _getAccountInformation(user);
    }

    function getUsdValue(address token, uint256 amount) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            /// PUBlic
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
    }

    function getTokenAmountFromUsd(address collateralToken, uint256 amountUsdInWei18Decimals)
        public
        ///Public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);

        (, int256 price,,,) = priceFeed.latestRoundData();

        return (amountUsdInWei18Decimals * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    ////////////////////////////////////////////////////////////////////////////////

    //                           TEST FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPs() external view returns (address) {
        return address(i_ps);
    }

    function getCollateralTokenPriceFeedAddress(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }
    //////////////////////////////////////////////////////////////

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}

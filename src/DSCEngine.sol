//SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ShadyStableCoin} from "./ShadyStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Kuusho
 * This Engine implements the logic for a Shady StableCoin.
 * The goal is to design a minimal engine for our decentralized stablecoin.
 * Our stablecoin has the following properties:
 * - Exogenous Collateral / Crypto Collateral (ETH & BTC)
 * - Dollar-Pegged
 * - Algorithmically Stable
 * - Overcollateralized
 *
 * It is similar to DAI but has no governance component, no fees and is only backed by wETH and wBTC.
 *
 * Our SSC system should always be overcollateralized.
 *
 * It should always have collateral that is more than the value of all SSC in USD terms
 *
 * @notice This contract is the core of the SSC system.
 * it handles all logic for mining and redeeming SSC as well as depositing and withdrawing collateral.
 *
 * @notice This contract is very loosely based on the MakerDAO DAI stablecoin system
 */

contract DSCEngine is ReentrancyGuard {
    /////////////
    // ERRORS //
    /////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBelowMinimum();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /////////////
    // TYPES //
    /////////////

    using OracleLib for AggregatorV3Interface;

    ///////////////////
    //STATE VARIABLES//
    ///////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant MAX_COLLATERAL_VALUE_USD = 1e30;
    uint256 private constant MAX_SSC_SUPPLY = 1e24;
    uint256 private constant MAX_HEALTH_FACTOR = 1000 * PRECISION;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountSscMinted) private s_sscMinted;
    ShadyStableCoin private immutable i_ssc;
    address[] private s_collateralTokens;

    ///////////////////
    //     EVENTS   //
    ///////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    /////////////
    //MODIFIERS//
    /////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////
    //FUNCTIONS//
    /////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address sscAddress
    ) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_ssc = ShadyStableCoin(sscAddress);
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral. see: depositCollateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountSscToMint The amount of Ssc to mint for a user after collateral is deposited
     */

    function depositCollateralAndMintSsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountSscToMint
    ) external {
        require(
            amountCollateral <= MAX_COLLATERAL_VALUE_USD,
            "Collateral amount too high"
        );
        require(amountSscToMint <= MAX_SSC_SUPPLY, "SSC mint amount too high");
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintSsc(amountSscToMint);
    }

    /**
     * @notice Follows CEI: Checks, Effects, Interactions
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // {
        //     uint256 currentCollateralValue = getUsdValue(
        //         tokenCollateralAddress,
        //         s_collateralDeposited[msg.sender][tokenCollateralAddress]
        //     );
        //     uint256 newCollateralValue = getUsdValue(
        //         tokenCollateralAddress,
        //         amountCollateral
        //     );
        //     require(
        //         currentCollateralValue + newCollateralValue <=
        //             MAX_COLLATERAL_VALUE_USD,
        //         "Exceeds maximum collateral value"
        //     );

        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The address of the token to redeem as collateral. see: redeemCollateral
     * @param amountCollateral the amount of collateral to redeem
     */

    function redeemCollateralForSsc(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            address(this),
            msg.sender
        );
    }

    // in order for a user to redeem collateral:
    // 1. Health Factor must be above 1 after collateral is pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        require(
            s_collateralDeposited[msg.sender][tokenCollateralAddress] >=
                amountCollateral,
            "Not enough collateral"
        );
        // These logs check for possible overflows due to large numbers
        console.log("Collateral value in USD:", amountCollateral);

        console.log(
            "User's total collateral before redemption:",
            s_collateralDeposited[msg.sender][tokenCollateralAddress]
        );

        console.log(
            "User's Health Factor Before redemption: ",
            _healthFactor(msg.sender)
        );

        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
        console.log(
            "User's total collateral after redemption:",
            s_collateralDeposited[msg.sender][tokenCollateralAddress]
        );
    }

    /**
     *
     * @param amountSscToMint Amount of SSC to mint
     */

    function mintSsc(
        uint256 amountSscToMint
    ) public moreThanZero(amountSscToMint) nonReentrant {
        s_sscMinted[msg.sender] += amountSscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_ssc.mint(msg.sender, amountSscToMint);

        if (minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnSsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // we'll likely not need
    }

    /**
     * @param collateral the erc20 token address of the collateral
     * @param user  the address of the user who is reaching or has reached their liquidation threshold
     * @param debtToCover the amount of SSC to burn for a user to reach a baseline health factor (MIN_HEALTH_FACTOR)
     *
     * @notice This function can let one user partially or totally liquidate another user whose health factor is below the minimum
     * @notice The user who calls the function will receive a liquidation bonus from the collateral of the user that has been liquidated
     * @notice The function assumes that the protocol is roughly 200% overcollateralized in order for this to work.
     * @notice If the protocol itself drops to 100% or less collateral, there will be no incentive for a user to participate as a Liquidator.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {}

    ////////////////////////////////
    //Internal & Private Functions//
    ////////////////////////////////

    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalSscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        if (totalSscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalSscMinted;
    }

    function _calculateHealthFactor(
        uint256 totalSscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalSscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalSscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalSscMinted, uint256 collateralValueInUsd)
    {
        totalSscMinted = s_sscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) internal {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        // require(
        //     amountCollateral <=
        //         s_collateralDeposited[from][tokenCollateralAddress],
        //     "Not enough collateral"
        // );
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @dev Low-Level DSC Burn Function, does not check if DSC is above minimum health factor
     * do not call this function if the user's health factor has been checked prior to calling this function
     */

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_sscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_ssc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_ssc.burn(amountDscToBurn);
    }

    ////////////////////////////////
    //Public & External View Functions//
    ////////////////////////////////

    function getAccountCollateralValueInUsd(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.stalePriceCheckLatestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalSscMinted, uint256 collateralValueInUsd)
    {
        (totalSscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getSscMinted(address user) external view returns (uint256) {
        return s_sscMinted[user];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPriceFeedAddress(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getTokenAmountFromUsdWithConsideration(
        address token,
        uint256 usdAmountInWei
    ) external view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.stalePriceCheckLatestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(
        uint256 totalSscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalSscMinted, collateralValueInUsd);
    }
}

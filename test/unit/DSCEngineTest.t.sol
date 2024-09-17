// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeploySsc} from "script/DeploySsc.s.sol";
import {ShadyStableCoin} from "src/ShadyStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeploySsc deployer;
    ShadyStableCoin ssc;
    DSCEngine ssce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address public user = makeAddr("USER");
    address public liquidator = makeAddr("LIQMAN");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant SSC_MINT_AMOUNT = 0.11 ether;

    function setUp() public {
        deployer = new DeploySsc();
        (ssc, ssce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    }

    /////////////////////
    // Constructor Tests //
    ////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(ssc));
    }

    /////////////////////
    // PriceFeed Tests //
    ////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = ssce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    // function testGetTokenAmountFromUsd() public view {
    //     uint256 usdAmount = 100 ether ;
    //     uint256 expectedWeth = 0.05 ether;
    //     uint256 actualWeth = ssce.getTokenAmountFromUsd(weth, usdAmount);
    //     assertEq(expectedWeth, actualWeth);

    //      // Test with a different token (e.g., WBTC)
    //     uint256 expectedBtcAmount = 0.005 ether; // Assuming 1 BTC = 20000 USD
    //     uint256 actualBtcAmount = ssce.getTokenAmountFromUsd(wbtc, usdAmount);

    //     // Assert
    //     assertEq(actualBtcAmount, expectedBtcAmount, "Incorrect BTC amount calculated");
    // }

    /////////////////////////////
    //DEPOSIT COLLATERAL TESTS//
    /////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(ssce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        ssce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        ssce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral {
        vm.startPrank(user, liquidator);
        ERC20Mock(weth).approve(address(ssce), AMOUNT_COLLATERAL);
        ssce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedSSc {
        vm.startPrank(user, liquidator);
        ERC20Mock(weth).approve(address(ssce), AMOUNT_COLLATERAL);
        ssce.depositCollateral(weth, AMOUNT_COLLATERAL);
        ssce.mintSsc(SSC_MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalSscMinted, uint256 collateralValueInUsd) = ssce.getAccountInformation(user);
        
        uint256 expectedTotalSscMinted = 0;
        uint256 expectedDepositAmount = ssce.getTokenAmountFromUsdWithConsideration(weth, collateralValueInUsd);
        assertEq(totalSscMinted, expectedTotalSscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    ////////////////////////////
    //MINT SSC TESTS//
    /////////////////////////////


    function testMintSsc() public depositedCollateral {
        vm.startPrank(user);
        ssce.mintSsc(SSC_MINT_AMOUNT);
        vm.stopPrank();

        (uint256 totalSscMinted, ) = ssce.getAccountInformation(user);
        assertEq(totalSscMinted, SSC_MINT_AMOUNT);
        
        uint256 userBalance = ssc.balanceOf(user);
        assertEq(userBalance, SSC_MINT_AMOUNT);
    }

    ////////////////////////////
    //REDEEM COLLATERAL TESTS//
    ////////////////////////////

    function testRedeemCollateral() public depositedCollateral {
    // ARRANGE    

        vm.startPrank(user);
        uint256 initialUserBalance = ERC20Mock(weth).balanceOf(user);
        ssce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance, AMOUNT_COLLATERAL + initialUserBalance);
        vm.stopPrank();
}

    function testRedeemCollateralFailsIfNotEnoughCollateral() public depositedCollateral {
        // Setup
        vm.startPrank(user);
        
        // Try to redeem more than deposited
        uint256 moreThanDeposited = AMOUNT_COLLATERAL + 1 ether;
        
        // Execute and Assert
        vm.expectRevert(); // Expect the transaction to revert
        ssce.redeemCollateral(weth, moreThanDeposited);
        vm.stopPrank();
    }

    function testRedeemCollateralFailsIfHealthFactorIsBroken() public depositedCollateral {
        // Setup
        vm.startPrank(user);
        ssce.mintSsc(50 ether); // Mint some SSC against the collateral
        
        // Try to redeem all collateral
        
        // Execute and Assert
        vm.expectRevert(); // Expect the transaction to revert due to broken health factor
        ssce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }


    ////////////////////////////
    //BURN SSC TESTS//
    /////////////////////////////

    function testBurnSsc() public depositedCollateral {
        uint256 amountToMint = 10 ether;
        uint256 amountToBurn = 5 ether;

        vm.startPrank(user);
        ssce.mintSsc(amountToMint);
        ssc.approve(address(ssce), amountToBurn);
        ssce.burnSsc(amountToBurn);
        vm.stopPrank();

        (uint256 totalSscMinted, ) = ssce.getAccountInformation(user);
        assertEq(totalSscMinted, amountToMint - amountToBurn);

        uint256 userBalance = ssc.balanceOf(user);
        assertEq(userBalance, amountToMint - amountToBurn);
    }


    ////////////////////////////
    //LIQUIDATE TESTS//
    /////////////////////////////
    

    function logPostLiquidationState(address _user, address _liquidator) internal view {
        console.log("User's health factor:", ssce.getHealthFactor(_user));
        console.log("User's remaining collateral:", ssce.getCollateralBalanceOfUser(_user, weth));
        console.log("User's remaining debt:", ssce.getSscMinted(_user));
        console.log("Liquidator's WETH balance:", ERC20Mock(weth).balanceOf(_liquidator));
        console.log("Liquidator's SSC balance:", ssce.getSscMinted(_liquidator));
    }
    
    ////////////////////////////
    //GETTER TESTS//
    /////////////////////////////


    function testGetHealthFactor() public depositedCollateral {

    vm.startPrank(user);
    ssce.mintSsc(SSC_MINT_AMOUNT);
    vm.stopPrank();

    (uint256 totalSscMinted, uint256 collateralValueInUsd) = ssce.getAccountInformation(user);
    console.log("Total SSC Minted:", totalSscMinted);
    console.log("Collateral Value in USD:", collateralValueInUsd);

    uint256 healthFactor = ssce.getHealthFactor(user);
    console.log("Actual Health Factor:", healthFactor);

    uint256 expectedHealthFactor = ssce.calculateHealthFactor(totalSscMinted, collateralValueInUsd);
    console.log("Expected Health Factor:", expectedHealthFactor);

    assertEq(healthFactor, expectedHealthFactor);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = ssce.getCollateralTokens();
        assertEq(collateralTokens.length, 2); // Assuming we have WETH and WBTC
        assertEq(collateralTokens[0], weth);
        assertEq(collateralTokens[1], wbtc);
    }

    function testGetPriceFeedAddresses() public view {
        address ethPriceFeed = ssce.getPriceFeedAddress(weth);
        address btcPriceFeed = ssce.getPriceFeedAddress(wbtc);
        assertEq(ethPriceFeed, ethUsdPriceFeed);
        assertEq(btcPriceFeed, btcUsdPriceFeed);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 ethCollateralBalance = ssce.getCollateralBalanceOfUser(user, weth);
        assertEq(ethCollateralBalance, AMOUNT_COLLATERAL);

        uint256 btcCollateralBalance = ssce.getCollateralBalanceOfUser(user, wbtc);
        assertEq(btcCollateralBalance, 0); // Assuming no BTC deposited
    }

    function testGetSscMinted() public depositedCollateral {
        uint256 initialSscMinted = ssce.getSscMinted(user);
        assertEq(initialSscMinted, 0);

        uint256 amountToMint = 100 ether;
        vm.startPrank(user);
        ssce.mintSsc(amountToMint);
        vm.stopPrank();

        uint256 finalSscMinted = ssce.getSscMinted(user);
        assertEq(finalSscMinted, amountToMint);
    }

    function testGetTokenAmountFromUsdWithConsideration() public view {
        uint256 usdAmount = 2000 ether; // $2000
        
        uint256 ethAmount = ssce.getTokenAmountFromUsdWithConsideration(weth, usdAmount);
        
        // Assuming 1 ETH = $2000, we expect 1 ETH
        assertEq(ethAmount, 1 ether);
    }

    function testGetLiquidationThreshold() public view {
        uint256 threshold = ssce.getLiquidationThreshold();
        assertEq(threshold, 50); // Assuming LIQUIDATION_THRESHOLD is set to 50
    }

    function testGetLiquidationBonus() public view {
        uint256 bonus = ssce.getLiquidationBonus();
        assertEq(bonus, 10); // Assuming LIQUIDATION_BONUS is set to 10
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = ssce.getMinHealthFactor();
        assertEq(minHealthFactor, 1e18); // Assuming MIN_HEALTH_FACTOR is set to 1 with 18 decimals
    }

    function testCalculateHealthFactor() public view {
        uint256 collateralValueInUsd = 200 ether; // $200 worth of collateral
        uint256 totalSscMinted = 100 ether; // 100 SSC minted
        
        uint256 healthFactor = ssce.calculateHealthFactor(totalSscMinted, collateralValueInUsd);
        
        // Expected health factor: (200 * 50 / 100) * 1e18 / 100 = 1e18
        assertEq(healthFactor, 1e18);
    }

    function testHealthFactorEdgeCases() public view {
        // Case 1: No SSC minted
        uint256 healthFactor1 = ssce.calculateHealthFactor(0, 1000 ether);
        assertEq(healthFactor1, type(uint256).max);

        // Case 2: No collateral
        uint256 healthFactor2 = ssce.calculateHealthFactor(100 ether, 0);
        assertEq(healthFactor2, 0);

        // Case 3: Equal collateral and minted SSC
        uint256 healthFactor3 = ssce.calculateHealthFactor(100 ether, 100 ether);
        assertEq(healthFactor3, 0.5e18); // 50% liquidation threshold
    }

    // ADDITIONAL TESTS
    
    function testRevertWhenMintingWithoutCollateral() public {
        vm.startPrank(user);
        vm.expectRevert();
        ssce.mintSsc(1 ether);
        vm.stopPrank();
    }

    function testRevertWhenMintingTooMuch() public depositedCollateral {
        vm.startPrank(user);
        uint256 maxSsc = ssce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2; // 50% of collateral value
        vm.expectRevert();
        ssce.mintSsc(maxSsc + 1);
        vm.stopPrank();
    }

    function testRevertWhenBurningMoreThanOwned() public depositedCollateralAndMintedSSc {
        vm.startPrank(user);
        vm.expectRevert();
        ssce.burnSsc(SSC_MINT_AMOUNT + 1);
        vm.stopPrank();
    }

    function testRevertWhenRedeemingMoreThanDeposited() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert();
        ssce.redeemCollateral(weth, AMOUNT_COLLATERAL + 1);
        vm.stopPrank();
    }

    function testRevertWhenRedeemingZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert();
        ssce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWhenBurningZero() public depositedCollateralAndMintedSSc {
        vm.startPrank(user);
        vm.expectRevert();
        ssce.burnSsc(0);
        vm.stopPrank();
    }

    function testRevertWhenMintingZero() public {   
        vm.startPrank(user);
        vm.expectRevert();
        ssce.mintSsc(0);
        vm.stopPrank();
    }

    function testRevertWhenDepositingZero() public {
        vm.startPrank(user);    
        vm.expectRevert();
        ssce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWhenDepositingUnapprovedCollateral() public {
        vm.startPrank(user);
        vm.expectRevert();
        ssce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }   

    function testRevertWhenRedeemingUnapprovedCollateral() public {
        vm.startPrank(user);
        vm.expectRevert();
        ssce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }   

    function testRevertWhenBurningUnapprovedSsc() public {  
        vm.startPrank(user);
        vm.expectRevert();  
        ssce.burnSsc(SSC_MINT_AMOUNT);
        vm.stopPrank();
    }

    function testRevertWhenLiquidatingWithInvalidCollateral() public depositedCollateralAndMintedSSc {
        ERC20Mock invalidToken = new ERC20Mock();
        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        ssce.liquidate(user, address(invalidToken), SSC_MINT_AMOUNT);
        vm.stopPrank();
    }

    function testMultipleCollateralDepositsAndRedemptions() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(ssce), AMOUNT_COLLATERAL * 2);
        ERC20Mock(wbtc).mint(user, AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(ssce), AMOUNT_COLLATERAL);

        ssce.depositCollateral(weth, AMOUNT_COLLATERAL);
        ssce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        ssce.depositCollateral(weth, AMOUNT_COLLATERAL);

        assertEq(ssce.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL * 2);
        assertEq(ssce.getCollateralBalanceOfUser(user, wbtc), AMOUNT_COLLATERAL);

        ssce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        ssce.redeemCollateral(wbtc, AMOUNT_COLLATERAL / 2);

        assertEq(ssce.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL);
        assertEq(ssce.getCollateralBalanceOfUser(user, wbtc), AMOUNT_COLLATERAL / 2);
        vm.stopPrank();
    }
}

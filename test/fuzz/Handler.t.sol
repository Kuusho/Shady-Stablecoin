//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ShadyStableCoin} from "../../src/ShadyStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine ssce;
    ShadyStableCoin ssc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, ShadyStableCoin _ssc) {
        ssce = _dscEngine;
        ssc = _ssc;

        address[] memory collateralTokens = ssce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(ssce.getPriceFeedAddress(address(weth)));
    }

    // redeemCollateral
    
    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = uint96(bound(amountCollateral, 1, MAX_DEPOSIT_SIZE));
        console.log("Bounded amountCollateral:", amountCollateral);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(ssce), amountCollateral);
        ssce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }


    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = ssce.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );
        console.log(
            "User Collateral Amout before redemptions in wei/weth",
            ssce.getCollateralBalanceOfUser(address(collateral), msg.sender)
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        require(
            amountCollateral <= ssce.getAccountCollateralValueInUsd(msg.sender),
            "Not enough collateral"
        );
        console.log("amountCollateral: ", amountCollateral);

        ssce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amountSscToMint, uint256  addressSeed) public {
        if (usersWithCollateralDeposited.length == 0){
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalSscMinted, uint256 collateralValueInUsd) = ssce
            .getAccountInformation(sender);

        int256 maxSscToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalSscMinted);

        if (maxSscToMint < 0) {
            return;
        }

        amountSscToMint = bound(amountSscToMint, 0, uint256(maxSscToMint));
        if (amountSscToMint == 0) {
            return;
        }

        vm.startPrank(sender);
        ssce.mintSsc(amountSscToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }


    // THIS BREAKS OUR SYSTEM AND INVARIANT
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // helper function
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

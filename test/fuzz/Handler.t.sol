//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ShadyStableCoin} from "../../src/ShadyStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine ssce;
    ShadyStableCoin ssc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, ShadyStableCoin _ssc) {
        ssce = _dscEngine;
        ssc = _ssc;

        address[] memory collateralTokens = ssce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
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
        console.log("User Collateral Amout before redemptions in wei/weth", ssce.getCollateralBalanceOfUser(address(collateral), msg.sender));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
           require(
            amountCollateral <=
                ssce.getAccountCollateralValueInUsd(msg.sender),
            "Not enough collateral"
        );
        console.log("amountCollateral: ", amountCollateral);
        
        ssce.redeemCollateral(address(collateral), amountCollateral);
    }

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

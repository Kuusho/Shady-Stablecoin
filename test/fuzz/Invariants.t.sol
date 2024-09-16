// SPDX-License-Identifier: MIT
// What are our Invatiants (proprties of the system that should always hold)?

// 1. Total SSC supply should be less that total collateral value
// 2. Getter functions should never revert

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeploySsc} from "../../script/DeploySsc.s.sol";
import {ShadyStableCoin} from "../../src/ShadyStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeploySsc public deployer;
    DSCEngine public ssce;
    ShadyStableCoin public ssc;
    HelperConfig public config;
    address public weth;
    address public wbtc;
    uint256 public amount = 20 ether;
    Handler handler;

    function setUp() external {
        deployer = new DeploySsc();
        (ssc, ssce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();

        handler = new Handler(ssce, ssc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = ssc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(ssce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(ssce));

        uint256 wethValue = ssce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = ssce.getUsdValue(wbtc, totalWbtcDeposited);
        
        console.log("weth value is: ", wethValue);
        console.log("wbtc value is: ", wbtcValue);
        console.log("Total Supply is: ", totalSupply);
        console.log("Times Mint is called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        ssce.getAccountCollateralValueInUsd(msg.sender);
        ssce.getAccountInformation(msg.sender);
        ssce.getCollateralBalanceOfUser(msg.sender, weth);
        ssce.getCollateralTokens();
        ssce.getHealthFactor(msg.sender);
        ssce.getLiquidationBonus();
        ssce.getUsdValue(weth, amount);
        ssce.getLiquidationThreshold();
        ssce.getMinHealthFactor();
        ssce.getPriceFeedAddress(weth);
        ssce.getSscMinted(msg.sender);
        ssce.getTokenAmountFromUsdWithConsideration(weth, amount);

    }
}

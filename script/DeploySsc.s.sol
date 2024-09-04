// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ShadyStableCoin} from "src/ShadyStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeploySsc is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;  

    
    function run() external returns (ShadyStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        ShadyStableCoin ssc = new ShadyStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(ssc));

        console.log(msg.sender);
        ssc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (ssc, engine, config);
    }
}

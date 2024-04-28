// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { DSCEngine } from "../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    DecentralizedStableCoin dsCoin;
    DSCEngine dscEngine;

    function run() external returns(
        DecentralizedStableCoin, 
        DSCEngine,
        HelperConfig
    ){
        HelperConfig config = new HelperConfig();

        (
            address wethUSDPriceFeed, 
            address wbtcUSDPriceFeed,
            address weth, 
            address wbtc, 
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];
        vm.startBroadcast(deployerKey);
        dsCoin = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(
            tokenAddresses, 
            priceFeedAddresses,
            address(dsCoin)
        );

        // Transfer ownership to the DSCEngine Contract
        dsCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsCoin, dscEngine, config);
    }

}
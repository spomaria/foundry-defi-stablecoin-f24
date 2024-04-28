// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script{
    
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 5000e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    // create a variable type that defines the return type for
    // each of the configurations
    struct NetworkConfig{
        address wethUSDPriceFeed; //wETHUSD price feed address
        address wbtcUSDPriceFeed; //wBTCUSD price feed address
        address weth; 
        address wbtc; 
        uint256 deployerKey;
    }

    // set the constructor function the selects the active network
    // configuration on deployment
    constructor(){
        // we use the chainid to determine the network of choice
        // and thereafter set the active network configuration
        if(block.chainid == 11155111){
            activeNetworkConfig = getSepoliaEthConfig();
        } else if(block.chainid == 1){
            activeNetworkConfig = getMainnetEthConfig();
        } else{
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns(NetworkConfig memory){
        
        NetworkConfig memory sepoliaNetworkConfig = NetworkConfig({
            wethUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUSDPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa,
            wbtc: 0xFF82bB6DB46Ad45F017e2Dfb478102C7671B13b3,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        return sepoliaNetworkConfig;
    }

    function getMainnetEthConfig() public view returns(NetworkConfig memory){
        
        NetworkConfig memory ethConfig = NetworkConfig({
            wethUSDPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            wbtcUSDPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });

        return ethConfig;
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory){
        // returns anvil price feed address

        // an address is only set once
        if(activeNetworkConfig.wethUSDPriceFeed != address(0)){
            return activeNetworkConfig;
        }

        // 1. Deploy the mocks
        // 2. return the mock contract address

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS, ETH_USD_PRICE
        );

        ERC20Mock wethMock = new ERC20Mock(); //ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS, BTC_USD_PRICE
        );

        ERC20Mock wbtcMock = new ERC20Mock(); //ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        return NetworkConfig({
            wethUSDPriceFeed: address(ethUsdPriceFeed),
            wbtcUSDPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }

}
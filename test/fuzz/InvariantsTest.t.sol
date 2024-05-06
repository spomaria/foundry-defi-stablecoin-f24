// SPDX-License-Identifier: MIT

// What are the invariants of the system? In other words, what the properties of the system that should always hold?

// 1. The total supply of DSC should be less than the total value of collateral

// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.18;

import { Test, console } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StopOnRevertHandler } from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    StopOnRevertHandler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        handler = new StopOnRevertHandler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanSupply() public view {
        // get the value of all collaterals in the protocol
        // compare it to the total DSC minted
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethUsdValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcUsdValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethUsdValue);
        console.log("wbtc value: ", wbtcUsdValue);
        console.log("dsc supply: ", totalSupply);
        console.log("Times Deposit called: ", handler.timesDepositCollateralIsCalled());
        console.log("Times mint called: ", handler.timesMintIsCalled());
        console.log("Times Redeem called: ", handler.timesRedeemCollateralIsCalled());

        assert(wethUsdValue + wbtcUsdValue >= totalSupply);
    }
}
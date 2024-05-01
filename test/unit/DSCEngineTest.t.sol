// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test, console } from "forge-std/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    /** Events */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public COLLATERAL_AMOUNT = 1 ether;
    uint256 public HALF_COLLATERAL_AMOUNT = 0.5 ether;
    uint256 public STARTING_ERC20_BALANCE = 10 ether;
    uint256 public ZERO_DSC = 0;
    uint256 public UNHEALTHY_DSC = 15000 ether; //15e21 > 1e22
    uint256 public HUNDRED_DSC = 0.1 ether;
    uint256 public FIFTY_DSC = 0.05 ether;
    uint256 public MIN_HEALTH_FACTOR = 1;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, ,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////
    //// Constructor Tests ////
    ///////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector
        );
        // vm.expectRevert();
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////////////
    ////  Price Feed Tests ////
    ///////////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30_000e18
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2_000 = 1 ETH, $100 = ?ETH 
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////////
    //// depositCollateral Tests ////
    /////////////////////////////////
    address ranAddress = makeAddr("randomAddress");

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = ERC20Mock(ranAddress);
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__TokenNotAllowed.selector
        );
        engine.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    modifier depositedCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanGetAccountInfo() public view {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = ZERO_DSC;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth, collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(ZERO_DSC, expectedDepositAmount);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = ZERO_DSC;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth, collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    function testEmitsEventOnDeposit() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectEmit(true, false, false, false, address(engine));
        // emit EnteredRaffle(PLAYER);
        emit CollateralDeposited(USER, weth, COLLATERAL_AMOUNT);
        // raffle.enterRaffle{value: entranceFee}();
        
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    ////////////////////////
    //// Mint DSC Tests ////
    ////////////////////////
    function testMintDscRevertsIfValueIsZero() public depositedCollateral {
        vm.expectRevert(
            DSCEngine.DSCEngine__MustBeMoreThanZero.selector
        );
        vm.startPrank(USER);
        engine.mintDsc(ZERO_DSC);
        vm.stopPrank();
    }

    function testMintDscRevertsWithoutPriorDeposit() public {
        vm.expectRevert();
        vm.startPrank(USER);
        engine.mintDsc(HUNDRED_DSC);
        vm.stopPrank();
    }

    function testMintDscRevertsIfMintingBreaksHealthFactor() public depositedCollateral {
        vm.expectRevert();
        vm.startPrank(USER);
        engine.mintDsc(UNHEALTHY_DSC);
        vm.stopPrank();
    }

    /////////////////////////////////
    /// Check Health Factor Tests ///
    /////////////////////////////////
    function testCanCheckHealthFactor() public view {
        uint256 userhealthFactor = engine.getHealthFactor(USER);
        (
            uint256 totalDscMinted, 
            uint256 collateralValueInUsd
        ) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, ZERO_DSC);
        assertEq(collateralValueInUsd, ZERO_DSC);
        assertEq(userhealthFactor, MIN_HEALTH_FACTOR);  
    }

    function testCanDepositCollateralAndCheckHealthFactor() public depositedCollateral {
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        (
            uint256 totalDscMinted, 
            uint256 collateralValueInUsd
        ) = engine.getAccountInformation(USER);
        console.log(collateralValueInUsd);
        console.log(userHealthFactor);
        assertEq(totalDscMinted, ZERO_DSC);
        assert(collateralValueInUsd > ZERO_DSC);
        assert(userHealthFactor > MIN_HEALTH_FACTOR);  
    }

    function testHealthFactorWorksAsExpected() public depositedCollateral {
        uint256 userStartHealthFactor = engine.getHealthFactor(USER);
        vm.startPrank(USER);
        engine.mintDsc(HUNDRED_DSC);
        vm.stopPrank();
        uint256 userEndHealthFactor = engine.getHealthFactor(USER);
        console.log(userStartHealthFactor);
        console.log(userEndHealthFactor);
        assert(userEndHealthFactor < userStartHealthFactor);
    }

    /////////////////////////////////////////////
    //// Deposit Collateral & Mint DSC Tests ////
    /////////////////////////////////////////////
    
    modifier depositedCollateralAndMintDsc(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, HUNDRED_DSC);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndMintDsc() public depositedCollateralAndMintDsc {
        (uint256 userBalance, ) = engine.getAccountInformation(USER);
        assertEq(userBalance, HUNDRED_DSC);
    }

    //////////////////////////////////////////////////
    //// Deposit Collateral, Mint & Burn DSC Tests ///
    //////////////////////////////////////////////////
    
    modifier depositCollateralMintAndBurnDsc(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, HUNDRED_DSC);
        dsc.approve(address(engine), FIFTY_DSC);
        engine.burnDsc(FIFTY_DSC);
        vm.stopPrank();
        _;
    }

    function testCanBurnMintedDsc() public depositCollateralMintAndBurnDsc {
        (uint256 userBalance, ) = engine.getAccountInformation(USER);
        assertEq(userBalance, FIFTY_DSC);
    }

    /////////////////////////////////
    //// Redeem Collateral Tests ////
    /////////////////////////////////
    
    modifier depositedAndRedeemCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        ERC20Mock(weth).approve(address(engine), HALF_COLLATERAL_AMOUNT);
        engine.redeemCollateral(weth, HALF_COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testRedeemCollateralRevertsIfValueIsZero() public depositedCollateral {
        vm.expectRevert(
            DSCEngine.DSCEngine__MustBeMoreThanZero.selector
        );
        vm.startPrank(USER);
        engine.redeemCollateral(weth, ZERO_DSC);
        vm.stopPrank();
        
    }

    function testCanRedeemCollateralIfValueIsNotZero() public depositedAndRedeemCollateral {
        uint256 endingCollateralAmount = engine.getCollateralAmountDeposited(weth, USER);

        assertEq(endingCollateralAmount, HALF_COLLATERAL_AMOUNT);
    }

    function testEmitsEventOnRedeemCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        ERC20Mock(weth).approve(address(engine), HALF_COLLATERAL_AMOUNT);
        
        vm.expectEmit(true, false, false, false, address(engine));
        // emit EnteredRaffle(PLAYER);
        emit CollateralRedeemed(USER, USER, weth, HALF_COLLATERAL_AMOUNT);
        // raffle.enterRaffle{value: entranceFee}();
        
        engine.redeemCollateral(weth, HALF_COLLATERAL_AMOUNT);
        vm.stopPrank();
    }
    /////////////////////////////////////
    //// redeemCollateralForDSC Tests ///
    /////////////////////////////////////
    
    modifier burnDscAndRedeemCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, HUNDRED_DSC);
        ERC20Mock(weth).approve(address(engine), HALF_COLLATERAL_AMOUNT);
        dsc.approve(address(engine), FIFTY_DSC);
        engine.redeemCollateralForDsc(weth, HALF_COLLATERAL_AMOUNT, FIFTY_DSC);
        vm.stopPrank();
        _;
    }

    function testCanRedeemCollateralForDsc() public burnDscAndRedeemCollateral {
        (uint256 userDscBalance,) = engine.getAccountInformation(USER);
        uint256 userCollateralBalance = engine.getCollateralAmountDeposited(weth, USER);
        assertEq(userDscBalance, FIFTY_DSC);
        assertEq(userCollateralBalance, HALF_COLLATERAL_AMOUNT);
    }

    ////////////////////////
    //// liquidate Tests ///
    ////////////////////////
    address RAN_USER = makeAddr("random_user");
    function testLiquidateRevertsIfDebtToCoverIsZero() public depositedCollateralAndMintDsc {
        vm.expectRevert(
            DSCEngine.DSCEngine__MustBeMoreThanZero.selector
        );
        vm.startPrank(RAN_USER);
        engine.liquidate(weth, USER, ZERO_DSC);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfHealthFactorIsOk() public depositedCollateralAndMintDsc {
        vm.expectRevert(
            DSCEngine.DSCEngine__HealthFactorOk.selector
        );
        vm.startPrank(RAN_USER);
        engine.liquidate(weth, USER, FIFTY_DSC);
        vm.stopPrank();
    }
    
}
// SPDX-License-Identifier: MIT

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
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.18;

import { DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title DSC Engine
/// @author Nengak Emmanuel Goltong
/// 
/// The Engine is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg
/// 
/// This StableCoin has the properties
/// - Exogenous Collateral
/// - Dolar Pegged
/// - Algorithmic
///
/// It is similar to DAI, if DAI had no governance, no fees, and was only bagged by wETH and wBTC
///
/// Our DSC system should always be 'overcollateralized'. At no point should the value of all collateral be <= the $ backed value of all the DSC
///
/// @notice This Contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral
/// @notice This Contract is VERY loosely based on makerDAO DSS (DAI) system

contract DSCEngine is ReentrancyGuard {
    ///////////////////////////
    ////      Errors   ///////
    //////////////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintingFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////////////
    //// State Variables //////
    //////////////////////////
    uint256 private constant ADDITIONAL_PRICE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollaterized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant ZERO_DSC = 0;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address tokenAddress => uint256 amount)) private s_CollateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    DecentralizedStableCoin immutable private i_dsc; 
    IERC20 private ierc20;
    address[] private s_collateralTokens;

    ///////////////////////////
    ////     Events      //////
    //////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    ///////////////////////////
    ////    Modifiers  ///////
    //////////////////////////
    modifier moreThanZero(uint256 amount) {
        if(amount == 0){
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier tokenIsAllowed(address token){
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////////////////////
    ////    Functions  ///////
    //////////////////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ){
        if(tokenAddresses.length != priceFeedAddresses.length){
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for(uint256 i; i < tokenAddresses.length;){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
            unchecked {
                i++;
            }
        }
        
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////
    // External Functions  ////
    //////////////////////////

    /**
    *
    * @param tokenCollateralAddress Address of the Collateral to be deposited
    * @param amountCollateral Amount of Collateral to deposit
    * @param amountDscToMint Amount of the DSC tokens to mint
    * */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        // msg.sender.approve(address(this), ZERO_DSC); // Reset the allowance to zero
        // msg.sender.approve(address(this), amountCollateral);
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
    * Follows CEI -- Checks, Effects, Interactions
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    * @notice This function lets you deposit your collateral
     */
    function depositCollateral (
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) tokenIsAllowed(tokenCollateralAddress) nonReentrant{
        s_CollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    /**
    * @param tokenCollateralAddress address of collateral to redeem
    * @param amountCollateral amount of collateral to redeem
    * @param amountDscToBurn amount of DSC token to burn
    * @notice this function burns DSC token and redeems collateral in one transaction
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks healthFactor
    }

    // In order to redeem collateral
    // healthFactor must be 1 AFTER collateral is pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
    }   

    /**
    * Follows CEI -- Checks, Effects, Interactions
    * @param amountDscToMint The amount of decentralized stable coin to mint
    * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted){
            revert DSCEngine__MintingFailed();
        }
    }

    
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //I don't think this is necessary
    }

    // If someone is almost undercollateralized, we will pay you liquidate them
    /**
    * @param collateral the erc20 collateral address to liquidate
    * @param user the user whose health factor is broken. their _healthFactor should be below MIN_HEALTH_FACTOR
    * @param debtToCover The amount of DSC to burn to improve the user's _healthFactor
    * @notice You can partially requidate a user.
    * @notice You will get a liquidation bonus for taking the user's funds
    * @notice This function working assumes the protocol will be 200% overcollateralized in order for this to work
    * @notice A known bug will be if the protocol is 100% or less collateralized, then we wouldn't be able to incentivize the liquidators
    * For example, if the price of the collateral plummeted before anyone could be liquidated
    * */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant{
        // check health factor of user
        uint256 startingHealthFactorOfUser = _healthFactor(user);
        if(startingHealthFactorOfUser >= MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }

        // We want to their DSC 'debt'
        // And take their collateral
        // Bad user: $140 of ETH and $100 of DSC
        // debtToCover: $100
        // $100 DSC == how much of the collateral?
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral,debtToCover);
        // And give them a 10% bonus
        // i.e we give $110 wETH for $100 DSC
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS)/ LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingHealthFactorOfUser = _healthFactor(user);
        if(endingHealthFactorOfUser <= startingHealthFactorOfUser){
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////
    // Private & Internal Functions  //
    ///////////////////////////////////

    /**
    * @dev Low-level internal function. Do not call unless the function calling it is checking if health factor is broken
    * */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(
        address from, address to, address tokenCollateralAddress, uint256 amountCollateral
    ) private moreThanZero(amountCollateral) {
        s_CollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(from, to, amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getAccountInformation(address user) private view returns(
        uint256 totalDSCMinted, 
        uint256 collateralValueInUsd
    ){
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
    * Returns how close to liquidation a user is
    * If a user goes below 1, then they can get liquidated
    * */
    function _healthFactor(address user) private view returns(uint256 healthFactor){
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // healthFactor = totalDscMinted == ZERO_DSC ? (collateralAdjustedForThreshold * PRECISION + MIN_HEALTH_FACTOR)/ (totalDscMinted + MIN_HEALTH_FACTOR): (collateralAdjustedForThreshold * PRECISION)/ totalDscMinted;
        healthFactor = totalDscMinted == ZERO_DSC ? (collateralAdjustedForThreshold + MIN_HEALTH_FACTOR)/ (totalDscMinted + MIN_HEALTH_FACTOR): collateralAdjustedForThreshold / totalDscMinted;
        
        // return (collateralAdjustedForThreshold * PRECISION)/ (totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////
    // Public & External Functions  //
    ///////////////////////////////////
    
    function getTokenAmountFromUsd(
        address token, uint256 usdAmountInWei
    ) public view returns(uint256){
        // Get the price of Collateral from Chainlink
        int256 price = getCollateralValue(token);
        return (usdAmountInWei * PRECISION)/(uint256(price) * ADDITIONAL_PRICE_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns(
        uint256 totalCollateralValueInUsd
    ) {
        for(uint256 i; i < s_collateralTokens.length;){
            address token = s_collateralTokens[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
            unchecked {
                i++;
            }
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        
        int256 price = getCollateralValue(token);
        uint256 usdValue = (uint256(price) * ADDITIONAL_PRICE_PRECISION * amount) / PRECISION;
        return usdValue;
    }

    function getCollateralValue(address token) public view returns(int256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price, , , ) = priceFeed.latestRoundData();
        
        return price;
    }

    function getAccountInformation(address user) external view returns(
        uint256 totalDscMinted, 
        uint256 collateralValueInUsd
    ){
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns(uint256 healthFactor){
        healthFactor = _healthFactor(user);
    }

    function getCollateralAmountDeposited(address token, address user) external view returns(uint256 amountDeposited) {
        amountDeposited = s_CollateralDeposited[user][token];
    }
}
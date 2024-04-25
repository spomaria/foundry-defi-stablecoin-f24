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

    ///////////////////////////
    //// State Variables //////
    //////////////////////////
    uint256 private constant ADDITIONAL_PRICE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollaterized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address tokenAddress => uint256 amount)) private s_CollateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    DecentralizedStableCoin immutable private i_dsc; 
    address[] private s_collateralTokens;

    ///////////////////////////
    ////     Events      //////
    //////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
    function depositCollateralAndMintDsc() external {}

    /**
    * Follows CEI -- Checks, Effects, Interactions
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral (
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral) tokenIsAllowed(tokenCollateralAddress) nonReentrant{
        s_CollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
    * Follows CEI -- Checks, Effects, Interactions
    * @param amountDscToMint The amount of decentralized stable coin to mint
    * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) external moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted){
            revert DSCEngine__MintingFailed();
        }
    }

    
    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///////////////////////////////////
    // Private & Internal Functions  //
    ///////////////////////////////////

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
    function _heathFactor(address user) private view returns(uint256){
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) /
            LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION)/ totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _heathFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////
    // Public & External Functions  //
    ///////////////////////////////////
    
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
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price, , , ) = priceFeed.latestRoundData();
        uint256 usdValue = (uint256(price) * ADDITIONAL_PRICE_PRECISION * amount) / PRECISION;
        return usdValue;
    }

}
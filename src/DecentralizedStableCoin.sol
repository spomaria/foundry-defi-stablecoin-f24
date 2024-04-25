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

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
/// @title DecentralizedStableCoin
/// @author Nengak Emmanuel Goltong
/// Collateral: Exogenous (ETH and BTC)
/// Minting: Algorithmic 
/// Relative Stability: Pegged to USD
///
/// This is the Contract meant to be governed by DSCEngine. This Contract is just the ERC20 implementation of our Stable Coin system.
/// 

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender){}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if( balance <= 0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if(balance < _amount){
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to, uint256 _amount
    ) external onlyOwner returns(bool){
        if(_to == address(0)){
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if( _amount <= 0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);

        return true;
    }
}
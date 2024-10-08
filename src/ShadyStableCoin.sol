//SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ShadyStableCoin - A shady StableCoin
 * @author Kuusho the chef
 * Collateral - Exogenous (ETH & BTC)
 * Minting - Algorithmic
 * Relative Stability - Pegged to USD
 * 
 * This stablecoin contract is simply an ERC-20 Implementation 
 * It will be governed by logic in the DSCEngine
 */
contract ShadyStableCoin is ERC20Burnable, Ownable{
    error ShadyStableCoin__MustBeMoreThanZero();
    error ShadyStableCoin__BurnAmountExceedsBalance();
    error ShadyStableCoin__NotZeroAddress();

    constructor () ERC20("ShadyStableCoin", "SSC") Ownable(address(msg.sender)){}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert ShadyStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert ShadyStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if (_to == address(0)) {
            revert ShadyStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert ShadyStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
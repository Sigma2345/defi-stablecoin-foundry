// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
 * @title Decentralized Stable Coin
 * @author Quaternion
 * Collateral: Exogenous (ETH or BTC)
 * Minting: Algorithmic
 * Relative Stability: Anchored (pegged)
 *
 * This contract is meant to be governed by DSCEngine.sol
 * This contracct is implementation of ERC20 version of our stable coin
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountMustBeGreaterThanBalance();
    error DecentralizedStableCoin__NotAddressZero();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 _balance = balanceOf(msg.sender);
        if (_amount <= 0) revert DecentralizedStableCoin__MustBeMoreThanZero();
        if (_amount > _balance) revert DecentralizedStableCoin__BurnAmountMustBeGreaterThanBalance();
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) revert DecentralizedStableCoin__NotAddressZero();
        if (_amount <= 0) revert DecentralizedStableCoin__MustBeMoreThanZero();
        _mint(_to, _amount);
        return true;
    }
}

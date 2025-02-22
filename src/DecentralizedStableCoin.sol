// SPDX-License-Identifier: MIT
/** 
Contract elements should be laid out in the following order:
Pragma statements
Import statements
Events
Errors
Interfaces
Libraries
Contracts
----------------
Inside each contract, library or interface, use the following order:
Type declarations
State variables
Events
Errors
Modifiers
Functions 
*/

pragma solidity 0.8.20;

import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol"; // nu stiu de ce nu merge @
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "forge-std/console.sol";

/**
 * @title Decentralized Stable Coin
 * @author Miu Vlad / Patrick Collins
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * This contract will be governed by DSCEngine
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountBurnedExceedsBalance();
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("Niu", "N") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
       
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balanceOf(msg.sender) < _amount) {
            revert DecentralizedStableCoin__AmountBurnedExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
    
}

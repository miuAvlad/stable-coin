// SPDX-License-Identifier: MIT
/**
 * Contract elements should be laid out in the following order:
 * Pragma statements
 * Import statements
 * Events
 * Errors
 * Interfaces
 * Libraries
 * Contracts
 * ----------------
 * Inside each contract, library or interface, use the following order:
 * Type declarations
 * State variables
 * Events
 * Errors
 * Modifiers
 * Functions
 */
pragma solidity 0.8.20;

import {Script,console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine,HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth,wbtc];
        priceFeedAddresses = [wethUsdPriceFeed,wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));

        // puteam sa dau deploy de pe primul contract probabil in constructor pentru a nu mai apela functia asta dar asa face baiatu asta greu poate e ceva good practice, idk
        dsc.transferOwnership(address(engine)); 
        vm.stopBroadcast();

        return(dsc,engine,helperConfig);
    }
}

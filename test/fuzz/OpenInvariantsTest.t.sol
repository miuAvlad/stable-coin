// // What are our invariants?

// // 1. the total suply of NIU should alwayse be less than total value of collateral

// // 2. Getter view functions should never revert <-- evergreen invariant

// // SPDX-License-Identifier: MIT
// /** 
// Contract elements should be laid out in the following order:
// Pragma statements
// Import statements
// Events
// Errors
// Interfaces
// Libraries
// Contracts
// ----------------
// Inside each contract, library or interface, use the following order:
// Type declarations
// State variables
// Events
// Errors
// Modifiers
// Functions 
// */

// pragma solidity 0.8.20;

// import {Test,console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


// contract OpenInvariantsTest is StdInvariant,Test{
//     DeployDSC deployer;
//     DSCEngine engine;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;


//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc,engine,config) = deployer.run();
//         (,,weth,wbtc,) = config.activeNetworkConfig();
//         targetContract(address(engine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         // get value of all the collateral in the protocol
//         // compare it to all debt 
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

//         uint256 wethValue = engine.getUsdValue(weth,totalWethDeposited);
//         uint256 wbtcValue = engine.getUsdValue(wbtc,totalWbtcDeposited);

//         console.log("Value of weth: ",wethValue);
//         console.log("Value of wbtc: ",wbtcValue);
//         console.log("Value of total supply: ",wbtcValue);

//         assert (wethValue + wbtcValue >= totalSupply);
//     }
// }
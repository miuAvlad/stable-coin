// What are our invariants?

// 1. the total suply of NIU should alwayse be less than total value of collateral

// 2. Getter view functions should never revert <-- evergreen invariant

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

import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";


contract InvariantsTest is StdInvariant,Test{
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;


    function setUp() external {
        deployer = new DeployDSC();
        (dsc,engine,config) = deployer.run();
        (,,weth,wbtc,) = config.activeNetworkConfig();
        // console.log("Engine balance of weth ",ERC20Mock(weth).balanceOf(address(engine)));
        handler = new Handler(engine,dsc);
        /**
         * @notice E acelasi lucru cu ce a facut el in video doar ca putin diferit
         * eu am mintat tokan-urilein variants, el le-a mintat in Handler
         * Logica e aceeasi dar adca hardcodez falorile astea crapa la testarea altor functii decat deposit si redeem
         */
        // ERC20Mock(weth).mint(address(handler),100e19);
        // ERC20Mock(wbtc).mint(address(handler),100e19);
     
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get value of all the collateral in the protocol
        // compare it to all debt 
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth,totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc,totalWbtcDeposited);

        console.log("Value of weth: ",wethValue);
        console.log("Value of wbtc: ",wbtcValue);
        console.log("Value of total supply: ",wbtcValue);
        console.log("Times mint called: ",handler.timesMintIsCalled());

        assert (wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        // engine.getAccountCollateralValue();
        // engine.getAccountInformation();
        // engine.getCollateralForUser();
        // engine.getCollaateralBallanceOfUser();
        engine.getCollateralTokens();

    }
}
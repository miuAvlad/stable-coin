// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSITED_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // uint256 maxCollateral = 100e18;
        // vm.assume(amountCollateral < maxCollateral);
        // vm.assume(amountCollateral > 0);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSITED_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        // ERC20Mock(address(collateral)).approve(address(engine), amountCollateral);
        // engine.depositCollateral(address(collateral),amountCollateral);
        usersWithCollateralDeposited.push(msg.sender);
    }

    /**
     * @notice Reverts if amountCollateral = 0 as expected
     * Reverts if breaks HealthFactor which is good
     * @param collateralSeed Used to calcuate address of token
     * @param amountCollateral Amount of collateral to be redeemed
     */
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollaateralBallanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        vm.assume(amountCollateral != 0);
        console.log("maxCollateralToRedeem: ", maxCollateralToRedeem);
        console.log("amountCollateral: ", amountCollateral);
        vm.prank(msg.sender);
        try engine.redeemCollateral(address(collateral), amountCollateral) {}
        catch (bytes memory errData) { 
            // bytes pentru ca erroarea in sine are 4 bytes dar daca are parametrii este primit ca vector de bytes 
            // errData este pointer
            // add(errData, 32) returneaza pointerul errData+32 (calcul 4bytes) sare peste primii 4 bytes care sunt metadata
            // mload(pointer de unde incepe sa citeasca) incarca 32 de bytes din memorie
            bytes4 errorSelector;
            assembly {
                errorSelector := mload(add(errData, 32)) 
            }
            if (errorSelector == DSCEngine.DSCEngine__BreaksHealthFactor.selector) {
                console.log("Error selector: ",uint32(errorSelector));
            } else {
                revert ("Error selector neasteptat!!"); // cond da revert cu o eroare diferita arata si eroarea 
            }
        }
    }

    function mintNiu(uint256 amountNiuToMint, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalNiuMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);

        int256 maxNiuToMint = (int256(collateralValueInUsd) / 2) - int256(totalNiuMinted);

        vm.assume(maxNiuToMint > 0);
        amountNiuToMint = bound(amountNiuToMint, 0, uint256(maxNiuToMint));
        vm.assume(amountNiuToMint != 0);

        vm.startPrank(sender);
        engine.mintNiu(amountNiuToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    //helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

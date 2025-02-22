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

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    ERC20Burnable, ERC20
} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol"; // nu stiu de ce nu merge @

contract DSCEnigneTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    address public SECOND_USER = makeAddr("user2");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_AMOUNT = 10 ether;
    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedNiu() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintNiu(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedNiuSecond() {
        vm.startPrank(SECOND_USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintNiu(weth, amountCollateral, 100*amountToMint);
        vm.stopPrank();
        _;
    }

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, 3 * STARTING_AMOUNT);
        ERC20Mock(weth).mint(SECOND_USER,  3 * STARTING_AMOUNT);

        // ERC20Mock(weth).mint(address(engine), 6 * STARTING_AMOUNT);
    }

    ///////////// Constructor Tests  ///////////

    function testRevertsIfTokenLengthDoesntmathcPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesLengthAndPriceFeedAdressesLengthDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(engine));
    }

    ///////////// Price Tests  ///////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assert(expectedUsd == actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assert(expectedWeth == actualWeth);
    }
    ///////////// Deposit Collateral Tests  ///////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "symbol");
        ranToken.mint(USER, STARTING_AMOUNT);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalNiuMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalNiuMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assert(totalNiuMinted == expectedTotalNiuMinted);
        assert(AMOUNT_COLLATERAL == expectedDepositAmount);
    }

    function testDepositCollateral() public depositedCollateral {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 actualAmountOfCollateral = engine.getCollateralForUser(USER, weth);
        uint256 amountCollateralExpected = (2 * AMOUNT_COLLATERAL);
        assertEq(actualAmountOfCollateral, amountCollateralExpected);
    }

    /**
     * Am testat aici si _burnNiu, si _healthFactor, teoretic si _revertIfHealthFactorIsBroken atunci cand am esuat cu impartirea la zero
     * Ar trebui sa testez si depositCollateralAndMintNiu dar pare ca merge ok
     */
    function testCanBurnNiu() public depositedCollateralAndMintedNiu {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        engine.burnNiu(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }
    function testBreakHealthFactorAfterMintingToMuchNiu() public {
        vm.startPrank(SECOND_USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        engine.depositCollateralAndMintNiu(weth, amountCollateral, 120*amountToMint);
        vm.stopPrank();
    }
    //////////////////////////////
    
    // aici da rever ERC20 nu intra in if

    function testRedeemCollateralFailDueToInsufficientBalance() public depositedCollateralAndMintedNiu {
        vm.prank(address(engine));
        IERC20(weth).transfer(USER, 10e18);
        vm.startPrank(USER);
        vm.expectRevert();
        engine.redeemCollateral(weth, 100);
        vm.stopPrank();
    }

    function testAmountCollateralDepositedAfterRedeem() public depositedCollateralAndMintedNiu {
        uint256 amountCollateralExpected = amountCollateral - 2;
        vm.startPrank(USER);
        engine.redeemCollateral(weth, 2);
        vm.stopPrank();

        assert(amountCollateralExpected == engine.getCollateralForUser(USER, weth));
    }
}

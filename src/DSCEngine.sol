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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "forge-std/console.sol";

/**
 * @title DSCEngine
 * @author Miu Vlad / Patrick Collins
 * This system is designe to be minimal and have tokens equals dollars
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * NIU should always be overcollateralized.
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC
 * @notice This contract is the core of the DSC System, it handles all the logic of minting, burning takoens, redeeming tokens as well as depositing and withdrawing collateral.
 * @notice This contract is verry loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////                        STATE VARIABLES                         /////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECIZION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountTokens) private s_NiuMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////                        EVENTS                         //////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    event CollateralDeposited(address indexed sender, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////                        ERRORS                         //////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    error DSCEngine__AmountMustBeGreaterThanZero();
    error DSCEngine__TokenAddressesLengthAndPriceFeedAdressesLengthDontMatch();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__ErrorInDepositingCollateral();
    error DSCEngine__BreaksHealthFactor();
    error DSCEngine__MintFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////                        MODIFIERS                      //////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////                        FUNCTIONS                      //////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesLengthAndPriceFeedAdressesLengthDontMatch();
        }
        for (uint8 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////                   EXTERNAL FUNCTIONS                      //////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    /**
     *
     * @param tokenCollateralAddress  The address of the token to deposit as collateral
     * @param amountCollateral The amount of colateral to be deposited
     * @param amountNiuToEmit The amount of tokens to be emitted
     * @notice This function will deposit your collateral and mint Niu in one transaction
     */
    function depositCollateralAndMintNiu(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountNiuToEmit
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintNiu(amountNiuToEmit);
    }

    /**
     * @notice Follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to be deposited
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant // common attack when working with external addresses
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__ErrorInDepositingCollateral();
        }
    }

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to be redeemed
     * @param amountNiuToBurn The amount of Niu to be burnt
     */
    function reedemCollateralForNiu(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountNiuToBurn)
        external
    {
        burnNiu(amountNiuToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // RedeemCollateral already checks health factor
    }

    // in order to redeem collateral :
    // 1. healt factor be over 1 after collateral pulled
    function redeemCollateral(address tokenCollaterlaAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemColateral(tokenCollaterlaAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amountNiuToMint The ammount of centralized stable coin to mint
     * @notice must have more collateral calue than the minimum threshold
     */
    function mintNiu(uint256 amountNiuToMint) public moreThanZero(amountNiuToMint) nonReentrant {
        s_NiuMinted[msg.sender] += amountNiuToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountNiuToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnNiu(uint256 amount) public moreThanZero(amount) {
        _burnNiu(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /**
     * @param collateral The erc20 collateral address to liquidate from  the user
     * @param user The user who broke the health factor
     * @param debtToCover The amount Niu to burn to imporve users health
     * @notice U can partially liquidate user
     */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        // console.log("Starting HealthFactor for user 2", startingUserHealthFactor);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // burn niu and take their collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // Give liquidator 10% bonus
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeam = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemColateral(collateral, totalCollateralToRedeam, user, msg.sender);
        _burnNiu(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactior = _healthFactor(user);
        // console.log("Ending HealthFactor for user 2", startingUserHealthFactor);
        if (endingUserHealthFactior <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////                   PRIVATE & INTERNAL FUNCTIONS                      ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    /**
     * @dev Low level internal function, do not call unless  the function calling it is chacking for health factors beeing broken
     */
    function _burnNiu(uint256 amountNiuToBurn, address onBehalfOf, address niuFrom) private {
        s_NiuMinted[onBehalfOf] -= amountNiuToBurn;
        bool success = i_dsc.transferFrom(niuFrom, address(this), amountNiuToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountNiuToBurn);
    }

    function _redeemColateral(address tokenCollaterlaAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // solidity compiler pentru unsafe math
        console.log("DSCEngine -> amountCollateral",amountCollateral);
        console.log("DSCEngine -> collateralDeposited",s_collateralDeposited[from][tokenCollaterlaAddress]);

        require(
            s_collateralDeposited[from][tokenCollaterlaAddress] >= amountCollateral, "Insufficient collateral to redeem"
        );
        s_collateralDeposited[from][tokenCollaterlaAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollaterlaAddress, amountCollateral);
        bool success = IERC20(tokenCollaterlaAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        // console.log("user: ",user );
        // console.log("user healthfactor < ",userHealthFactor );
        // console.log("min health factor ",MIN_HEALTH_FACTOR );
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor();
        }
    }

    /**
     * @notice Returns how close a user is to liquidation
     * @param user user
     */
    function _healthFactor(address user) private view returns (uint256) {
        // Total Niu minted
        // Total collateral value
        (uint256 totalNiuMinted, uint256 collateralValueInUsd) = _getAccountInformationFromUser(user);
        uint256 collateralAdjustedForThreshhold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        if (totalNiuMinted == 0) {
            return type(uint256).max;
        }
        return (collateralAdjustedForThreshhold * PRECIZION) / totalNiuMinted; // ce se intampla daca total niu minted este 0
    }

    function _getAccountInformationFromUser(address user)
        private
        view
        returns (uint256 totalNiuMinted, uint256 collateralValueInUsd)
    {
        totalNiuMinted = s_NiuMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////                  PUBLIC & EXTERNAL VIEW FUNCTIONS                      ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECIZION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 valueInUsdOfCollateral) {
        // loop trough each collateral token , get the amount deposited and get price into USD
        uint256 length = s_collateralTokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            valueInUsdOfCollateral += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]); // s_priceFeeds[token] e adresa de pe chainlink de la care se ia raportul ETH/USD
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECIZION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalNiuMinted, uint256 collateralValueInUsd)
    {
        (totalNiuMinted, collateralValueInUsd) = _getAccountInformationFromUser(user);
    }

    // Getters

    function getCollateralForUser(address user, address token) public returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollaateralBallanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/helperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcPriceFeed;
    address weth;
    address wbtc;
    address public USER = makeAddr("user");
    address public USER1 = makeAddr("user1");
    // 10 ether -> $20000 USD
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant TOKEN_TRANSFER_BALANCE = 1 ether;
    uint256 public constant USER1_STARTING_BALANCE = 2*STARTING_ERC20_BALANCE;
    uint256 public constant OVERDRAW_POINT = 20000e18 ; 

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER1, USER1_STARTING_BALANCE);
    }

    ///////////////////////////////
    /// CONSTRUCTOR TESTS /////////
    ///////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    
    function testRevertsIfTokenLengthIsNotEqualToPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses = [ethUsdPriceFeed, btcPriceFeed];
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////////
    /// PRICE TESTS //////////
    //////////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUSDValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether; 
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    ////////////////////////////////// 
    /// DEPOSIT COLLATERAL TESTS /////
    ////////////////////////////////// 

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral() {
        vm.startPrank(USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation();
        vm.stopPrank();
        uint256 expectedTotalDSCMinted = 0 ;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(address(weth), collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    ///////////////////////////////
    /// MINT DSC TESTS ////////////
    ///////////////////////////////
    
    function testMintDscFailsForZeroAmount() public depositCollateral() {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsBroken() public depositCollateral(){
        uint256 collateralAmountInUsd = dsce.getUSDValue(address(weth), AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        // after depositing collateral, the health factor is 2.0
        // after trannsacting collateral amount, health factor becomes 0.5e18 = 0.5e17
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 5e17));
        dsce.mintDsc(collateralAmountInUsd);
        vm.stopPrank();
    }

    function testMintDscUpdatesDscBalance() public depositCollateral(){
        uint256 collateralAmountInUsd = dsce.getUSDValue(address(weth), AMOUNT_COLLATERAL);
        uint256 dscMinted = collateralAmountInUsd/10 ; 
        vm.startPrank(USER);
        dsce.mintDsc(dscMinted);
        vm.stopPrank(); 
        uint256 expectedDscBalance = dscMinted;
        uint256 actualDscBalance = dsc.balanceOf(USER);
        assertEq(expectedDscBalance, actualDscBalance);
    }

    /////////////////////////////////
    /// BURN DSC TESTS //////////////
    /////////////////////////////////

    modifier approveReceiver() {
        uint256 collateralAmountInUsd = dsce.getUSDValue(address(weth), AMOUNT_COLLATERAL);
        uint256 dscMinted = collateralAmountInUsd/10 ;
        vm.startPrank(USER);
        dsc.approve(address(dsce), dscMinted);
        vm.stopPrank(); 
        _; 
    }

    function testRevertsIfMoreDscBurnThanMinted() public depositCollateral() {
        uint256 collateralAmountInUsd = dsce.getUSDValue(address(weth), AMOUNT_COLLATERAL);
        uint256 dscMinted = collateralAmountInUsd/10 ; 
        vm.startPrank(USER);
        dsce.mintDsc(dscMinted);
        vm.expectRevert(DSCEngine.DSCEngine__BurningMoreDscThanMintedByUser.selector);
        dsce.burnDsc(dscMinted + 1);
        vm.stopPrank();
    }   

    function testBurnDscUpdatesBalanceDsc() public depositCollateral() approveReceiver() {
        uint256 collateralAmountInUsd = dsce.getUSDValue(address(weth), AMOUNT_COLLATERAL);
        uint256 dscMinted = collateralAmountInUsd/10 ; 
        vm.startPrank(USER);
        dsce.mintDsc(dscMinted);
        uint256 initialDscBalance = dsc.balanceOf(USER);
        dsce.burnDsc(dscMinted);
        vm.stopPrank();
        uint256 predictedFinalDscBalance = 0; 
        uint256 actualFinalDscBalance = dsc.balanceOf(USER);
        assertEq(initialDscBalance, dscMinted);
        assertEq(actualFinalDscBalance, predictedFinalDscBalance);
    }

    ////////////////////////
    /// LIQUIDATE TESTS ////
    ////////////////////////

    modifier user2DepositCollateral {
        
        _;
    } 

    function testRevertsWhenUserTrieToLiquidateHealthyUser() public depositCollateral() approveReceiver() {

    }
    
} 


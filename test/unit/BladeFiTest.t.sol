// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BladeFi} from "../../src/BladeFi.sol";
import {DeployBladeFi} from "../../script/DeployBladeFi.s.sol";
import {USDC} from "../../src/USDC.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "../mocks/AggregatorV3Interface.sol";

contract BladeFiTest is Test, USDC {
    BladeFi bladeFi;
    HelperConfig helperConfig;
    USDC usdc;
    address wusdcUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address wusdc;
    address wbtc;
    uint256 deployerKey;

    int256 public constant BTC_USD_PRICE = 1000e8;
    int256 public constant USDC_USD_PRICE = 1e8;
    uint256 constant STARTING_USDC_BALANCE = 1000;
    address public PLAYER1 = makeAddr("player1");
    address public PLAYER2 = makeAddr("player2");
    address public PLAYER3 = makeAddr("player3");
    address public LP1 = makeAddr("lp1");
    address public LP2 = makeAddr("lp2");
    address usdcPriceFeedAddr = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address btcPriceFeedAddr = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    function setUp() external {
        DeployBladeFi deployer = new DeployBladeFi();

        (usdc, bladeFi, helperConfig) = deployer.run();
        usdc.mint(PLAYER1, STARTING_USDC_BALANCE);
        usdc.mint(PLAYER2, STARTING_USDC_BALANCE);
        usdc.mint(LP1, 1000000000);
        usdc.mint(LP2, 1000000000);
        (
            wusdcUsdPriceFeed,
            wbtcUsdPriceFeed,
            wusdc,
            wbtc,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
    }

    modifier approvingTransferOfTokens(address user, uint256 amount) {
        vm.prank(user);
        usdc.approve(address(bladeFi), amount);
        _;
    }

    modifier provideSufficientLiquidity(address lp, uint256 amount) {
        vm.prank(lp);
        usdc.approve(address(bladeFi), amount);
        vm.prank(lp);
        bladeFi._deposit(amount);
        _;
    }

    function testDepositIsNotGreaterThanZeroRevert() public {
        vm.prank(PLAYER1);
        vm.expectRevert("Deposit less than zero");
        bladeFi._deposit(0);
    }

    function testIfDepositIncreasesLPsAssets()
        public
        approvingTransferOfTokens(PLAYER1, 100)
    {
        vm.prank(PLAYER1);
        bladeFi._deposit(100);
        uint256 assetsHeld = bladeFi.s_shareHolder(PLAYER1);
        assert(assetsHeld == 100);
    }

    function testIfTotalLqDepositedChangesAfterDeposit()
        public
        approvingTransferOfTokens(PLAYER1, 100)
        approvingTransferOfTokens(PLAYER2, 100)
    {
        vm.prank(PLAYER1);
        bladeFi._deposit(100);
        vm.prank(PLAYER2);
        bladeFi._deposit(100);
        uint256 totalLqDeposited = bladeFi.totalLqDepositedInUsd();
        assert(totalLqDeposited == 200);
    }

    function testCollateralAmountIsNotGreaterThanZeroRevert() public {
        vm.prank(PLAYER1);
        vm.expectRevert("Collateral less than zero");
        bladeFi.depositCollateral(0);
    }

    function testIfTradersCollateralIncreasesAfterDeposit()
        public
        approvingTransferOfTokens(PLAYER1, 100)
    {
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(100);
        uint256 collateralHeld = bladeFi.s_collateral(PLAYER1);
        assert(collateralHeld == 100);
    }

    function testIfInsufficientLeverageCanBeUsedToOpenALongPosition()
        public
        approvingTransferOfTokens(PLAYER1, 1)
    {
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(1);
        vm.prank(PLAYER1);
        vm.expectRevert(BladeFi.BladeFi__MaxLeverageExceeded.selector);
        bladeFi.openLong(100);
    }

    function testIfLongLeverage20IsAcceptedAndEventsAreEmittedOnSuccess()
        public
        approvingTransferOfTokens(PLAYER1, 100000)
        provideSufficientLiquidity(LP1, 10000000)
    {
        usdc.mint(PLAYER1, 1000000);
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(100000);
        vm.prank(PLAYER1);
        vm.recordLogs();
        bladeFi.openLong(2000);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 openedLong = entries[0].topics[0];

        assertEq(openedLong, keccak256("LongPositionOpened(address,uint256)"));
    }

    function testIfShortLeverage20IsAcceptedAndEventsAreEmittedOnSuccess()
        public
        approvingTransferOfTokens(PLAYER1, 100000)
        provideSufficientLiquidity(LP1, 10000000)
    {
        usdc.mint(PLAYER1, 1000000);

        vm.prank(PLAYER1);
        bladeFi.depositCollateral(100000);
        vm.prank(PLAYER1);
        vm.recordLogs();
        bladeFi.openShort(2000);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 openedShort = entries[0].topics[0];

        assertEq(
            openedShort,
            keccak256("ShortPositionOpened(address,uint256)")
        );
    }

    function testIfLongOpenInterestIsUpdated()
        public
        approvingTransferOfTokens(PLAYER1, 100)
        provideSufficientLiquidity(LP1, 10000)
    {
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(100);
        vm.prank(PLAYER1);
        bladeFi.openLong(1);
        uint256 longOpenInterestInUsd = bladeFi.longOpenInterestInUsd();
        uint256 longOpenInterestInTokens = bladeFi.longOpenInterestInTokens();
        assertEq(longOpenInterestInUsd, 1000);
        assertEq(longOpenInterestInTokens, 1);
    }

    function testIfShortOpenInterestIsUpdated()
        public
        approvingTransferOfTokens(PLAYER1, 100)
        provideSufficientLiquidity(LP1, 10000)
    {
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(100);
        vm.prank(PLAYER1);
        bladeFi.openShort(1);
        uint256 shortOpenInterestInUsd = bladeFi.shortOpenInterestInUsd();
        uint256 shortOpenInterestInTokens = bladeFi.shortOpenInterestInTokens();
        assertEq(shortOpenInterestInUsd, 1000);
        assertEq(shortOpenInterestInTokens, 1);
    }

    function testIfWithdrawWithNoSharesIsPossible()
        public
        approvingTransferOfTokens(PLAYER1, 100)
    {
        vm.prank(PLAYER1);
        vm.expectRevert();
        bladeFi.withdraw(PLAYER1, PLAYER1, address(bladeFi), 100, 0);
    }

    function testIfWithdrawRevertsWithZeroAddrAsReceiver()
        public
        approvingTransferOfTokens(PLAYER1, 100)
    {
        vm.prank(PLAYER1);
        bladeFi._deposit(100);

        uint256 shares = bladeFi.s_shareHolder(PLAYER1);
        vm.prank(PLAYER1);
        vm.expectRevert();

        bladeFi.withdraw(PLAYER1, address(0), address(bladeFi), 100, shares);
    }

    function testIfTheWithdrawerHasToBeAShareholderWithShares()
        public
        approvingTransferOfTokens(PLAYER1, 100)
    {
        vm.prank(PLAYER1);
        vm.expectRevert(BladeFi.BladeFi__NotEnoughShares.selector);

        bladeFi.withdraw(PLAYER1, PLAYER1, address(bladeFi), 100, 10);
    }

    function testTotalDepositsIsCalculatedCorrectly()
        public
        approvingTransferOfTokens(PLAYER1, 100)
        approvingTransferOfTokens(PLAYER2, 100)
    {
        vm.prank(PLAYER1);
        bladeFi._deposit(100);
        vm.prank(PLAYER2);
        bladeFi._deposit(100);
        uint256 totalDeposits = bladeFi.totalDeposits();
        assertEq(totalDeposits, 200);
    }

    function testTotalPnLOfTradersIsCalculatedCorrectly()
        public
        approvingTransferOfTokens(PLAYER1, 200)
        approvingTransferOfTokens(PLAYER2, 100)
        provideSufficientLiquidity(LP1, 10000)
    {
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(200);
        vm.prank(PLAYER1);
        bladeFi.openLong(3);
        vm.prank(PLAYER2);
        bladeFi.depositCollateral(100);
        vm.prank(PLAYER2);
        bladeFi.openShort(2);
        int256 totalPnLOfTraders = (bladeFi.totalPnLOfTraders());
        assertEq(totalPnLOfTraders, (1 * BTC_USD_PRICE) / 1e8);
    }

    function testTotalAssetsAreCalculatedProperly()
        public
        approvingTransferOfTokens(PLAYER1, 200)
        approvingTransferOfTokens(PLAYER2, 100)
        approvingTransferOfTokens(LP1, 10000)
    {
        usdc.mint(LP1, 100000);
        vm.prank(LP1);
        bladeFi._deposit(10000);
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(200);
        vm.prank(PLAYER1);
        bladeFi.openLong(2);
        vm.prank(PLAYER2);
        bladeFi.depositCollateral(100);
        vm.prank(PLAYER2);
        bladeFi.openShort(1);
        // total LP deposits : 10000 USD
        // total open interest: 1000 USD
        // totalAssets = 9000 USD
        uint256 totalAssets = bladeFi.totalAssets();
        int256 totalPnL = bladeFi.totalPnLOfTraders();
        uint256 totalDeposits = bladeFi.totalDeposits();
        assertEq(totalPnL, 1000);
        assertEq(totalDeposits, 10000);
        assertEq(totalAssets, 9000);
    }

    function testGetAccountCollateralValueCalculatesProperly()
        public
        approvingTransferOfTokens(PLAYER1, 100)
    {
        vm.prank(PLAYER1);
        bladeFi.depositCollateral(100);
        uint256 collateralValue = bladeFi.getAccountCollateralValue(PLAYER1);
        assertEq(collateralValue, 100);
    }

    function testGetUsdValueChoosesTheCorrectPriceFeed() public {
        uint256 usdValue = bladeFi.getUsdValue(wbtc, 1000);
        assertEq(usdValue, 1000000);
    }
    /**

Uncovered for src/BladeFi.sol:
- Branch (branch: 1, path: 1) (location: source ID 34, line 145, chars 4576-4620, hits: 0)
- Line (location: source ID 34, line 147, chars 4688-4735, hits: 0)
- Statement (location: source ID 34, line 147, chars 4688-4735, hits: 0)
- Branch (branch: 2, path: 0) (location: source ID 34, line 147, chars 4688-4735, hits: 0)
- Branch (branch: 2, path: 1) (location: source ID 34, line 147, chars 4688-4735, hits: 0)
- Line (location: source ID 34, line 149, chars 4818-4877, hits: 0)
- Statement (location: source ID 34, line 149, chars 4818-4877, hits: 0)
- Branch (branch: 3, path: 0) (location: source ID 34, line 149, chars 4818-4877, hits: 0)
- Branch (branch: 3, path: 1) (location: source ID 34, line 149, chars 4818-4877, hits: 0)
- Line (location: source ID 34, line 150, chars 4887-4922, hits: 0)
- Statement (location: source ID 34, line 150, chars 4887-4922, hits: 0)
- Line (location: source ID 34, line 151, chars 4932-4988, hits: 0)
- Statement (location: source ID 34, line 151, chars 4932-4988, hits: 0)
- Branch (branch: 5, path: 0) (location: source ID 34, line 165, chars 5449-5520, hits: 0)
- Line (location: source ID 34, line 166, chars 5477-5509, hits: 0)
- Statement (location: source ID 34, line 166, chars 5477-5509, hits: 0)
- Function "totalAssets" (location: source ID 34, line 222, chars 7322-7493, hits: 0)
- Function "totalDeposits" (location: source ID 34, line 227, chars 7499-7599, hits: 0)
- Function "totalPnLOfTraders" (location: source ID 34, line 231, chars 7605-7797, hits: 0)
- Function "getAccountCollateralValue" (location: source ID 34, line 237, chars 7803-8083, hits: 0)
- Function "getUsdValue" (location: source ID 34, line 246, chars 8089-8466, hits: 0)
 */
}

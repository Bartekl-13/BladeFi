// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {USDC} from "./USDC.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// interface AutomationCompatibleInterface {
//     /**
//      * @notice method that is simulated by the keepers to see if any work actually
//      * needs to be performed. This method does does not actually need to be
//      * executable, and since it is only ever simulated it can consume lots of gas.
//      * @dev To ensure that it is never called, you may want to add the
//      * cannotExecute modifier from KeeperBase to your implementation of this
//      * method.
//      * @param checkData specified in the upkeep registration so it is always the
//      * same for a registered upkeep. This can easily be broken down into specific
//      * arguments using `abi.decode`, so multiple upkeeps can be registered on the
//      * same contract and easily differentiated by the contract.
//      * @return upkeepNeeded boolean to indicate whether the keeper should call
//      * performUpkeep or not.
//      * @return performData bytes that the keeper should call performUpkeep with, if
//      * upkeep is needed. If you would like to encode data to decode later, try
//      * `abi.encode`.
//      */
//     function checkUpkeep(
//         bytes calldata checkData
//     ) external returns (bool upkeepNeeded, bytes memory performData);

//     /**
//      * @notice method that is actually executed by the keepers, via the registry.
//      * The data returned by the checkUpkeep simulation will be passed into
//      * this method to actually be executed.
//      * @dev The input to this method should not be trusted, and the caller of the
//      * method should not even be restricted to any single registry. Anyone should
//      * be able call it, and the input should be validated, there is no guarantee
//      * that the data passed in is the performData returned from checkUpkeep. This
//      * could happen due to malicious keepers, racing keepers, or simply a state
//      * change while the performUpkeep transaction is waiting for confirmation.
//      * Always validate the data passed in.
//      * @param performData is the data which was passed back from the checkData
//      * simulation. If it is encoded, it can easily be decoded into other types by
//      * calling `abi.decode`. This data should not be trusted, and should be
//      * validated against the contract's current state.
//      */
//     function performUpkeep(bytes calldata performData) external;
// }

contract BladeFi is ERC4626, ReentrancyGuard {
    //////////////
    /// Errors ///
    //////////////
    error BladeFi__TransferFailed();
    error BladeFi__MaxLeverageExceeded();

    /////////////////////////
    //// State Variables ////
    /////////////////////////

    // struct for managing positions
    struct Position {
        uint256 longAmount;
        uint256 shortAmount;
        uint256 leverage;
        uint256 pnl;
    }

    address private immutable i_usdc;
    address private immutable i_btc;
    address public latestTrader;

    // mapping of LPs to their share tokens (vUSDC)
    mapping(address => uint256) public s_shareHolder;
    // mapping of traders to their positions
    mapping(address => Position) public s_positions;
    // mapping of traders to their collateral (USDC)
    mapping(address => uint256) public s_collateral;
    // mapping of price feeds
    mapping(address => address) public s_priceFeeds;

    uint256 public reservedLiquidity;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    uint256 public totalLqDepositedInUsd;
    uint256 public totalLqDepositedInTokens;
    uint256 public longOpenInterestInUsd;
    uint256 public longOpenInterestInTokens;
    uint256 public shortOpenInterestInUsd;
    uint256 public shortOpenInterestInTokens;

    bool newDeposit;
    //////////////////
    ///// Events /////
    //////////////////
    event CollateralDeposited(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address token,
        uint256 amount
    );

    /////////////////
    /// Modifiers ///
    /////////////////

    /**
     * @notice modifier to check if max leverage is exceeded
     * At the same time checks if user has ANY collateral
     */
    modifier isLeverageAcceptable(uint256 amountToBorrow, address trader) {
        if (
            getAccountCollateralValue(trader) * 20 >=
            getUsdValue(i_btc, amountToBorrow)
        ) {
            revert BladeFi__MaxLeverageExceeded();
        }
        _;
    }

    ///////////////////
    //// Functions ////
    ///////////////////

    // USDC/USD sepolia price feed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
    // BTC/USD sepolia price feed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
    constructor(
        ERC20 _asset,
        address _assetToBorrow,
        address[] memory priceFeedAddresses,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        i_usdc = address(_asset);
        i_btc = address(_assetToBorrow);
        s_priceFeeds[i_usdc] = address(priceFeedAddresses[0]);
        s_priceFeeds[i_btc] = address(priceFeedAddresses[1]);
    }

    /**
     * TODO:
     * 1. Function for opening a position - long or short
     * 2. Base the amount of BTC available to borrow on the collateral and Chainlink Price Feed of BTC/USD,
     * let the value of USDC be a constant 1 USD
     *
     * If max leverage = 20: maxAssetsBorrowed = collateral * 20
     * if (leverage > 20) {
     *    revert;
     * }
     *
     * 3. Function to increase a position - modify Position struct according to the new pricefeed
     * */

    /**
     * @notice function to deposit assets and receive vault token in exchange
     * @param _assets amount of the asset token
     */
    function _deposit(uint _assets) public {
        // checks that the deposited amount is greater than zero.
        require(_assets > 0, "Deposit less than Zero");
        // calling the deposit function ERC-4626 library to perform all the functionality
        deposit(_assets, msg.sender);
        // Increase the share of the user
        s_shareHolder[msg.sender] += _assets;
        newDeposit = true;
        totalLqDepositedInUsd += getUsdValue(i_usdc, _assets);
        totalLqDepositedInTokens += _assets;
    }

    /**
     * @notice overriding internal function from the ERC4626 library
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        // checks that the deposited amount is greater than zero.
        require(shares > 0, "withdraw must be greater than Zero");
        // Checks that the _receiver address is not zero.
        require(receiver != address(0), "Zero Address");
        // checks that the caller is a shareholder and has enough shares
        require(s_shareHolder[msg.sender] > 0, "Not enough shares");

        _withdraw(caller, receiver, owner, assets, shares);

        s_shareHolder[msg.sender] -= shares;
    }

    function depositCollateral(uint256 amountCollateral) public nonReentrant {
        // require the deposit to be greater than zero
        require(amountCollateral > 0, "Deposit must be greater than zero");
        // increase the trader's collateral

        s_collateral[msg.sender] += amountCollateral;
        emit CollateralDeposited(msg.sender, amountCollateral);
        bool success = IERC20(i_usdc).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert BladeFi__TransferFailed();
        }
        // update the total collateral in this contract
        latestTrader = msg.sender;
    }

    function openLong(
        uint256 amount
    ) public nonReentrant isLeverageAcceptable(amount, msg.sender) {
        s_positions[msg.sender].longAmount = amount;
        s_positions[msg.sender].leverage =
            getUsdValue(i_btc, amount) /
            getAccountCollateralValue(msg.sender);
        updateLongOpenInterest(amount);
    }

    function openShort(
        uint256 amount
    ) public nonReentrant isLeverageAcceptable(amount, msg.sender) {
        s_positions[msg.sender].shortAmount = amount;
        s_positions[msg.sender].leverage =
            getUsdValue(i_btc, amount) /
            getAccountCollateralValue(msg.sender);
        updateShortOpenInterest(amount);
    }

    function updateLongOpenInterest(uint256 amount) internal {
        longOpenInterestInUsd += getUsdValue(i_btc, amount);
        longOpenInterestInTokens += amount;
    }

    function updateShortOpenInterest(uint256 amount) internal {
        shortOpenInterestInUsd += getUsdValue(i_btc, amount);
        shortOpenInterestInTokens += amount;
    }

    // function checkUpkeep(
    //     bytes calldata checkData
    // ) external override returns (bool upkeepNeeded, bytes memory performData) {
    //     bool depositHappened = newDeposit;

    //     upkeepNeeded = (depositHappened);
    //     return (upkeepNeeded, "0x0");
    // }

    // function performUpkeep(bytes calldata performData) external override {
    //     if (!newDeposit) {} else {
    //         newDeposit = false;
    //     }
    // }

    /**
     * @notice overriding view function from ERC4626 library
     */
    function totalAssets() public view override returns (uint256) {
        uint256 total = uint256(int256(totalDeposits()) - totalPnLOfTraders());
        return total;
    }

    function totalDeposits() public view returns (uint256) {
        return totalLqDepositedInUsd;
    }

    function totalPnLOfTraders() public view returns (int256) {
        int256 totalPnl = int256(longOpenInterestInUsd) -
            int256(shortOpenInterestInUsd);
        return totalPnl;
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 amount = s_collateral[user];
        totalCollateralValueInUsd += getUsdValue(i_usdc, amount);

        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}

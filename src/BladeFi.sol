// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {USDC} from "./USDC.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface AutomationCompatibleInterface {
    /**
     * @notice method that is simulated by the keepers to see if any work actually
     * needs to be performed. This method does does not actually need to be
     * executable, and since it is only ever simulated it can consume lots of gas.
     * @dev To ensure that it is never called, you may want to add the
     * cannotExecute modifier from KeeperBase to your implementation of this
     * method.
     * @param checkData specified in the upkeep registration so it is always the
     * same for a registered upkeep. This can easily be broken down into specific
     * arguments using `abi.decode`, so multiple upkeeps can be registered on the
     * same contract and easily differentiated by the contract.
     * @return upkeepNeeded boolean to indicate whether the keeper should call
     * performUpkeep or not.
     * @return performData bytes that the keeper should call performUpkeep with, if
     * upkeep is needed. If you would like to encode data to decode later, try
     * `abi.encode`.
     */
    function checkUpkeep(
        bytes calldata checkData
    ) external returns (bool upkeepNeeded, bytes memory performData);

    /**
     * @notice method that is actually executed by the keepers, via the registry.
     * The data returned by the checkUpkeep simulation will be passed into
     * this method to actually be executed.
     * @dev The input to this method should not be trusted, and the caller of the
     * method should not even be restricted to any single registry. Anyone should
     * be able call it, and the input should be validated, there is no guarantee
     * that the data passed in is the performData returned from checkUpkeep. This
     * could happen due to malicious keepers, racing keepers, or simply a state
     * change while the performUpkeep transaction is waiting for confirmation.
     * Always validate the data passed in.
     * @param performData is the data which was passed back from the checkData
     * simulation. If it is encoded, it can easily be decoded into other types by
     * calling `abi.decode`. This data should not be trusted, and should be
     * validated against the contract's current state.
     */
    function performUpkeep(bytes calldata performData) external;
}

contract BladeFi is AutomationCompatibleInterface, ERC4626, ReentrancyGuard {
    //////////////
    /// Errors ///
    //////////////
    error BladeFi__TransferFailed();

    /////////////////////////
    //// State Variables ////
    /////////////////////////

    // struct for managing positions
    struct Position {
        address trader;
        uint256 amount;
        uint256 leverage;
        uint256 pnl;
    }

    address private immutable i_usdc;

    // mapping of LPs to their share tokens (vUSDC)
    mapping(address => uint256) public s_shareHolder;
    // mapping of traders to their positions
    mapping(address => Position) public s_positions;
    // mapping of traders to their collateral (USDC)
    mapping(address => uint256) public s_collateral;

    uint256 public totalCollateral;
    uint256 public reservedLiquidity;
    uint256 public pnl;

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

    ///////////////////
    //// Functions ////
    ///////////////////
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        i_usdc = asset();
    }

    /**
     * @notice overriding view function from ERC4626 library
     */
    function totalAssets() public view override returns (uint256) {
        uint256 total = totalDeposits() - totalPnLOfTraders();
        return total;
    }

    function totalDeposits() public view returns (uint256) {
        return totalCollateral;
    }

    function totalPnLOfTraders() public view returns (uint256) {
        return pnl;
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
        totalCollateral += amountCollateral;
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
        // checks that the caller is a shareholder
        require(s_shareHolder[msg.sender] > 0, "Not a shareHolder");
        // checks that the caller has more shares than they are trying to withdraw.
        require(s_shareHolder[msg.sender] >= shares, "Not enough shares");
        // Calculate 10% yield on the withdraw amount
        _withdraw(caller, receiver, owner, assets, shares);

        s_shareHolder[msg.sender] -= shares;
    }

    //   /**
    //  * @dev This is the function that the Chainlink Automation nodes call to see if it's time to perform an upkeep.
    //  *  The following should be true to return true:
    //  * 1. The time interval has passed between raffle runs
    //  * 2. The raffle is in the OPEN state
    //  * 3. Contract has ETH (players)
    //  * 4. (Implicit) The subscription is funded with LINK
    //  */
    // function checkUpkeep(
    //     bytes memory /* checkData */
    // ) public view returns (bool upKeepNeeded, bytes memory /* performData */) {
    //     bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
    //     bool isOpen = RaffleState.OPEN == s_raffleState;
    //     bool hasBalance = address(this).balance > 0;
    //     bool hasPlayers = s_players.length > 0;
    //     upKeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
    //     return (upKeepNeeded, "0x0");
    // }

    // // Get a random number, use the random number to pick a player
    // // Be automatically called
    // function performUpkeep(bytes calldata /* performData */) external {
    //     (bool upKeepNeeded, ) = checkUpkeep("");
    //     if (!upKeepNeeded) {
    //         revert Raffle__UpkeepNotNeeded(
    //             address(this).balance,
    //             s_players.length,
    //             uint256(s_raffleState)
    //         );
    //     }
    //     s_raffleState = RaffleState.CALCULATING; // Thanks to that, while calculating people would be unable to enter the raffle
    //     uint256 requestId = i_vrfCoordinator.requestRandomWords(
    //         i_gasLane,
    //         i_subscriptionId,
    //         REQUEST_CONFIRMATIONS,
    //         i_callbackGasLimit,
    //         NUM_WORDS
    //     );

    //     emit RequestedRaffleWinner(requestId);
    // }
    function checkUpkeep(
        bytes calldata checkData
    ) external override returns (bool upkeepNeeded, bytes memory performData) {}

    function performUpkeep(bytes calldata performData) external override {}
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {USDC} from "../../src/USDC.sol";
import {Test, console} from "forge-std/Test.sol";

contract USDCTest is Test, USDC {
    USDC usdc;

    address public PLAYER1 = makeAddr("player1");
    address public PLAYER2 = makeAddr("player2");

    uint256 constant INITIAL_SUPPLY = 100;

    function setUp() external {
        vm.prank(PLAYER1);
        usdc = new USDC();
    }

    function testMintIncreasesRecipientBalance() public {
        uint256 initialBalance = usdc.balanceOf(PLAYER1);
        usdc.mint(PLAYER1, 50);
        uint256 finalBalance = usdc.balanceOf(PLAYER1);
        assertEq(finalBalance, initialBalance + 50);
    }

    function testMintIncreasesTotalSupply() public {
        uint256 initialSupply = usdc.totalSupply();
        usdc.mint(PLAYER1, 50);
        uint256 finalSupply = usdc.totalSupply();
        assertEq(finalSupply, initialSupply + 50);
    }

    function testDecimals() public {
        uint8 decimals = usdc.decimals();
        assertEq(decimals, 18);
    }

    function testAddressThis() public {
        address contractAddress = usdc.addressThis();
        assertEq(contractAddress, address(usdc));
    }

    function testInitialSupplyAndBalance() public {
        uint256 totalSupply = usdc.totalSupply();
        uint256 player1Balance = usdc.balanceOf(PLAYER1);
        uint256 player2Balance = usdc.balanceOf(PLAYER2);

        assertEq(totalSupply, INITIAL_SUPPLY);
        assertEq(player1Balance, INITIAL_SUPPLY);
        assertEq(player2Balance, 0);
    }

    function testTransfer() public {
        vm.prank(PLAYER1);
        usdc.transfer(PLAYER2, 20);
        uint256 player1Balance = usdc.balanceOf(PLAYER1);
        uint256 player2Balance = usdc.balanceOf(PLAYER2);

        assertEq(player1Balance, INITIAL_SUPPLY - 20);
        assertEq(player2Balance, 20);
    }

    function testAllowance() public {
        vm.prank(PLAYER1);
        usdc.approve(PLAYER2, 40);
        uint256 allowance = usdc.allowance(PLAYER1, PLAYER2);
        assertEq(allowance, 40);
    }
}

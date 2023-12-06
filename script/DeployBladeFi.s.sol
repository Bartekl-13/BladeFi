// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {USDC} from "../src/USDC.sol";
import {BladeFi} from "../src/BladeFi.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployBladeFi is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (USDC, BladeFi, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with mocks!

        (
            address usdcUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address usdc,
            address wbtc,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        priceFeedAddresses = [usdcUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        ERC20 usdcToken = ERC20(usdc);

        BladeFi bladeFi = new BladeFi(
            usdcToken,
            wbtc,
            priceFeedAddresses,
            "VaultUSDC",
            "vUSDC"
        );

        vm.stopBroadcast();
        return (USDC(usdc), bladeFi, helperConfig);
    }
}

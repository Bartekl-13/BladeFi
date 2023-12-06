// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;

    int256 public constant BTC_USD_PRICE = 1000e8;
    int256 public constant USDC_USD_PRICE = 1e8;

    struct NetworkConfig {
        address usdcUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address usdc;
        address wbtc;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig()
        public
        view
        returns (NetworkConfig memory sepoliaNetworkConfig)
    {
        sepoliaNetworkConfig = NetworkConfig({
            usdcUsdPriceFeed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            usdc: 0x884b1c96e1b4c4F1D49526028d79947d7DAC1E0A,
            wbtc: 0x5A0fE8d6A17C3ef65f0Db6c4dC1b221db3808cF8,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig()
        public
        returns (NetworkConfig memory anvilNetworkConfig)
    {
        // Check to see if we set an active network config
        if (activeNetworkConfig.wbtcUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        MockV3Aggregator usdcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            USDC_USD_PRICE
        );

        ERC20Mock usdcMock = new ERC20Mock("USDC", "USDC", msg.sender, 1e8);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            usdcUsdPriceFeed: address(usdcUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            usdc: address(usdcMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}

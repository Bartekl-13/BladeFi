// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BladeFi} from "../src/BladeFi.sol";

contract DeployBladeFi is Script {
    function run() external returns (BladeFi) {
        vm.startBroadcast();
        BladeFi bladeFi = new BladeFi();
        vm.stopBroadcast();
        return bladeFi;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

contract StakingScript is Script {
    StakingRewards public staking;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        staking = new StakingRewards(
            0x925c164A113D7fbF28D31f4838A39c30Ee881c9e,
            0x1bFa922fa026c6Be6E1a930018437319ea85F8c9
        );

        vm.stopBroadcast();
    }
}

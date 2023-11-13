// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mock/LinkToken.sol";
import {MockERC20} from "../test/mock/MockERC20.sol";
import {Callisto} from "../src/CallistoToken.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address _callistoToken;
        uint256 _lotteryExpiry;
        uint256 _ticketPrice;
        address _vrfCoordinator;
        uint64 _subsciptionID;
        address _linkToken;
        uint256 _deployerKey;
    }

    NetworkConfig public activeConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeConfig = getSepoliaEthConfig();
        } else {
            activeConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            _ticketPrice: 0.01 ether,
            _lotteryExpiry: 10 minutes,
            _callistoToken: 0x15768cd3e37Ad3a4FEA33703dF4DAC1Ee7a43efd,
            _vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            _subsciptionID: 1082,
            _linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            _deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeConfig._vrfCoordinator != address(0)) {
            return activeConfig;
        }

        LinkToken linkToken = new LinkToken();

        vm.startBroadcast();
        MockERC20 callistoToken = new MockERC20(msg.sender);
        VRFCoordinatorV2Mock vrfCoordinatorMock = new VRFCoordinatorV2Mock(
            0.25 ether,
            1e9
        );
        vm.stopBroadcast();

        return NetworkConfig({
            _ticketPrice: 0.01 ether,
            _lotteryExpiry: 10 minutes,
            _vrfCoordinator: address(vrfCoordinatorMock),
            _callistoToken: address(callistoToken),
            _subsciptionID: 0,
            _linkToken: address(linkToken),
            _deployerKey: vm.envUint("ANVIL_DEFAULT_PRIVATE_KEY")
        });
    }
}

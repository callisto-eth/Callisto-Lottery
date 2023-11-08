// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CallistoLotto} from "../src/CallistoLotto.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interaction.s.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract DeployRaffle is Script {
    function run() external returns (CallistoLotto, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address _callistoToken,
            uint256 _lotteryExpiry,
            uint256 _ticketPrice,
            address _vrfCoordinator,
            uint64 _subscriptionID,
            address _linkToken,
            uint256 _deployerKey
        ) = helperConfig.activeConfig();

        if (_subscriptionID == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            _subscriptionID = createSubscription.createSubscription(
                _vrfCoordinator,
                _deployerKey
            );

            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                _vrfCoordinator,
                _subscriptionID,
                _linkToken,
                _deployerKey
            );
        }

        console.log("Subscription ID: ", _subscriptionID);

        vm.startBroadcast();
        CallistoLotto newRaffle = new CallistoLotto(
            _subscriptionID,
            _vrfCoordinator,
            _callistoToken,
            _lotteryExpiry,
            _ticketPrice
        );
        vm.stopBroadcast();
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(newRaffle),
            _vrfCoordinator,
            _subscriptionID,
            _deployerKey
        );
        return (newRaffle, helperConfig);
    }
}

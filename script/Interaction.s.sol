// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mock/LinkToken.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {CallistoLotto} from "../src/CallistoLotto.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , , address vrfCoordinator, , , uint256 _deployerKey) = helperConfig
            .activeConfig();
        return createSubscription(vrfCoordinator, _deployerKey);
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 _deployerKey
    ) public returns (uint64) {
        console.log("Creating a Subscription on ChainID: ", block.chainid);
        vm.startBroadcast(_deployerKey);
        uint64 subscriptionID = VRFCoordinatorV2Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Create Subscription ID: ", subscriptionID);
        return subscriptionID;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 1 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            ,
            address _vrfCoordinator,
            uint64 _subscriptionID,
            address _linkToken,
            uint256 _deployerKey
        ) = helperConfig.activeConfig();
        fundSubscription(
            _vrfCoordinator,
            _subscriptionID,
            _linkToken,
            _deployerKey
        );
    }

    function fundSubscription(
        address _vrfCoordinator,
        uint64 _subscriptionID,
        address _linkToken,
        uint256 _deployerKey
    ) public {
        console.log("Funding subscription: ", _subscriptionID);
        console.log("Using vrfCoordinator: ", _vrfCoordinator);
        console.log("On ChainID: ", block.chainid);
        if (block.chainid == 31337) {
            vm.startBroadcast(_deployerKey);
            VRFCoordinatorV2Mock(_vrfCoordinator).fundSubscription(
                _subscriptionID,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(_linkToken).transferAndCall(
                _vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(_subscriptionID)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address _raffleAddr,
        address _vrfCoordinator,
        uint64 _subscriptionID,
        uint256 _deployerKey
    ) public {
        console.log("Adding Consumer Contract: ", _raffleAddr);
        console.log("VRFCoordinator: ", _vrfCoordinator);
        console.log("ChainID: ", block.chainid);
        vm.startBroadcast(_deployerKey);

        VRFCoordinatorV2Mock vrfCoordinator = VRFCoordinatorV2Mock(
            _vrfCoordinator
        );

        vrfCoordinator.addConsumer(_subscriptionID, _raffleAddr);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address _contractAddress) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            ,
            address _vrfCoordinator,
            uint64 _subscriptionID,
            ,
            uint256 _deployerKey
        ) = helperConfig.activeConfig();
        addConsumer(
            _contractAddress,
            _vrfCoordinator,
            _subscriptionID,
            _deployerKey
        );
    }

    function run() external {
        address contractAddress = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerUsingConfig(contractAddress);
    }
}

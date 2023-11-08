// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {CallistoLotto} from "../src/CallistoLotto.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {VRFCoordinatorV2Mock} from "../src/mock/VRFCoordinatorV2Mock.sol";

contract CallistoLottoTest is Test {
    MockERC20 CALLISTO;
    VRFCoordinatorV2Mock COORDINATOR;
    CallistoLotto LOTTO;
    uint64 subId;

    function setUp() public {
        CALLISTO = new MockERC20(address(this));
        COORDINATOR = new VRFCoordinatorV2Mock(100000000000000000, 1000000000);
        LOTTO = new CallistoLotto(1, address(COORDINATOR), address(CALLISTO), 10, 1000000000000000000); // 10s lotto time, 1 token entry price
        subId = COORDINATOR.createSubscription();
        COORDINATOR.fundSubscription(subId, 100 ether);
        COORDINATOR.addConsumer(subId, address(LOTTO));
    }

    function test_buyTicket() public {
        CALLISTO.mint(address(1), 1000000000000000000);
        vm.startPrank(address(1));
        CALLISTO.approve(address(LOTTO), 1000000000000000000);
        LOTTO.buyTicket([1, 2, 3, 4, 5]);
        assertEq(CALLISTO.balanceOf(address(0)), 0);
        assertEq(CALLISTO.balanceOf(address(LOTTO)), 1000000000000000000);
    }

    function test_endLotto() public {
        vm.warp(block.timestamp + 10);
        uint256 requestId = LOTTO.endLotto();
        COORDINATOR.fulfillRandomWords(requestId, address(this));
    }

    // Should fail if the expiry time is not met
    function testFail_endLotto() public {
        LOTTO.endLotto();
    }

    function test_startNextLotto() public {
        vm.warp(block.timestamp + 10);
        uint256 requestId = LOTTO.endLotto();
        COORDINATOR.fulfillRandomWords(requestId, address(LOTTO));
        LOTTO.startNextLotto();
        assertEq(LOTTO.currentLottoId(), 1); // Ensures lottoId went from 0 -> 1
    }

    // Checks if a ticket gets claimed
    function test_claimTicket() public {
        CALLISTO.mint(address(1), 1000000000000000000);
        vm.startPrank(address(1));
        CALLISTO.approve(address(LOTTO), 1000000000000000000);
        uint256 ticketId = LOTTO.buyTicket([1, 2, 3, 4, 5]);
        vm.warp(block.timestamp + 10);
        uint256 requestId = LOTTO.endLotto();
        COORDINATOR.fulfillRandomWords(requestId, address(LOTTO));
        LOTTO.startNextLotto();
        LOTTO.claimTicket(ticketId);
    }
}

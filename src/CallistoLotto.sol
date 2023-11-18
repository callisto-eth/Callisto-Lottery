// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFCoordinatorV2Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "chainlink-brownie-contracts/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title A unique take on the lottery game by Callisto Labs
/// @author @0xKits
/// @notice This contract is a lottery game which uses ERC721 tokens as tickets. Powered by Chainlink VRF.
/// @dev Contract is NOT audited. Use at your own risk

contract CallistoLotto is VRFConsumerBaseV2, ERC721 {
    event NewLotteryStarted(uint256 lottoId, uint256 startTime);
    event LotteryEnded(uint256 lottoId, uint256 endTime);
    event LotteryResultDrawn(uint256 lottoId, uint8[(5)] winningNumbers);
    event TicketPurchased(address buyer, uint256 ticketId, uint8[(5)] numbers);
    event TicketClaimed(address claimer, uint256 ticketId, uint256 prizePoolShare);

    struct LotteryInstance {
        uint256 startTime;
        uint256 prizePool;
        uint256 claimedAmount;
        uint256 seed;
        uint8[(5)] winningNumbers;
        LotteryStatus status;
    }

    struct Ticket {
        uint256 lottoId;
        uint8[(5)] numbers;
        bool claimed;
    }

    enum LotteryStatus {
        IN_PLAY,
        VRF_REQUESTED,
        SETTLED
    }

    mapping(uint256 => LotteryInstance) lottoIdToLotto;
    mapping(uint256 => uint256) requestIdToLottoId;
    mapping(uint256 => Ticket) ticketIdToTicket;
    mapping(uint256 => mapping(uint256 => mapping(uint8 => uint256))) lottoIdToPositionToNumberToCounter;

    uint256 public ticketPrice;
    uint256 public currentLottoId;
    uint256 public expiry;
    uint256 currentTicketId;

    IERC20 CALLISTO;

    VRFCoordinatorV2Interface COORDINATOR;

    uint64 s_subscriptionId;

    bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint32 callbackGasLimit = 200000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 1;

    /**
     * HARDCODED FOR SEPOLIA
     * COORDINATOR: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
     *
     */

    /**
     * SHIT REQUIRED BY VRF PLEASE IGNORE
     *
     */

    constructor(
        uint64 subscriptionId,
        address coordinator,
        address callistoToken,
        uint256 _expiry,
        uint256 _ticketPrice
    ) ERC721("Callisto Lottery Ticket", "CTKT") VRFConsumerBaseV2(coordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(coordinator);
        s_subscriptionId = subscriptionId;
        CALLISTO = IERC20(callistoToken);
        expiry = _expiry;
        ticketPrice = _ticketPrice;
        lottoIdToLotto[currentLottoId] =
            LotteryInstance(block.timestamp, 0, 0, 0, [0, 0, 0, 0, 0], LotteryStatus.IN_PLAY);
    }

    /**
     * Lottery Lifecycle Logic
     *
     */

    function startNextLotto() public {
        require(newLottoStartable(), "Lottery: Either lotto is in play or VRF has been requested");

        currentLottoId++;
        lottoIdToLotto[currentLottoId] =
            LotteryInstance(block.timestamp, 0, 0, 0, [0, 0, 0, 0, 0], LotteryStatus.IN_PLAY);

        emit NewLotteryStarted(currentLottoId, block.timestamp);
    }

    function drawLottoResult(uint256 seed) internal {
        lottoIdToLotto[currentLottoId].seed = seed;
        lottoIdToLotto[currentLottoId].status = LotteryStatus.SETTLED;
        lottoIdToLotto[currentLottoId].winningNumbers = drawWinningNumbers(seed);

        emit LotteryResultDrawn(currentLottoId, lottoIdToLotto[currentLottoId].winningNumbers);
    }

    function endLotto() public returns (uint256 requestId) {
        require(currentLottoEndable(), "Lottery: Either lotto is in play or VRF has been requested");

        lottoIdToLotto[currentLottoId].status = LotteryStatus.VRF_REQUESTED;
        uint256 _requestId =
            COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
        requestIdToLottoId[_requestId] = currentLottoId;

        emit LotteryEnded(currentLottoId, block.timestamp);

        return (_requestId);
    }

    /**
     * Ticket purchasing logic
     *
     */

    function buyTicket(uint8[(5)] memory numbers) public returns (uint256 ticketId) {
        require(isValidNumbers(numbers), "Lottery: Invalid set of numbers!");

        require(
            canBuyTickets(), "Lottery: Either lotto has been settled, VRF has been requested or is awaiting closure"
        );

        CALLISTO.transferFrom(msg.sender, address(this), ticketPrice);

        currentTicketId++;
        _safeMint(msg.sender, currentTicketId);

        ticketIdToTicket[currentTicketId] = Ticket(currentLottoId, numbers, false);

        lottoIdToLotto[currentLottoId].prizePool += ticketPrice;

        for (uint256 i = 0; i < 5; i++) {
            incrementNumberPos(i, numbers[i]);
        }

        emit TicketPurchased(msg.sender, currentTicketId - 1, numbers);
        return (currentTicketId);
    }

    /**
     * Ticket Claim Logic
     *
     */

    function claimTicket(uint256 ticketId) public {
        require(ownerOf(ticketId) == msg.sender, "Lottery: You don't own this ticket!");

        require(
            lottoIdToLotto[ticketIdToTicket[ticketId].lottoId].status == LotteryStatus.SETTLED,
            "Lottery: The requested lottery instance is not settled"
        );

        require(!ticketIdToTicket[ticketId].claimed, "Lottery: Nice try, you've already claimed this ticket");

        ticketIdToTicket[ticketId].claimed = true;
        uint8[(5)] memory numbers = getTicketNumbers(ticketId);
        uint256 prizePoolShare = getPrizePoolShare(ticketIdToTicket[ticketId].lottoId, numbers);
        lottoIdToLotto[ticketIdToTicket[ticketId].lottoId].claimedAmount += prizePoolShare;

        CALLISTO.transfer(msg.sender, prizePoolShare);

        emit TicketClaimed(msg.sender, ticketId, prizePoolShare);
    }

    /**
     *  Internal functions
     *
     */

    function fulfillRandomWords(uint256, uint256[] memory _randomWords) internal override {
        drawLottoResult(_randomWords[0]);
    }

    function getPrizePoolShare(uint256 lottoId, uint8[(5)] memory numbers) internal view returns (uint256 share) {
        for (uint256 i = 0; i < 5; i++) {
            if (numbers[i] == lottoIdToLotto[lottoId].winningNumbers[i]) {
                uint256 nc = getNumberCount(lottoId, i, numbers[i]);
                share += (lottoIdToLotto[lottoId].prizePool) / (5 * nc);
            }
        }
        return (share);
    }

    function canBuyTickets() internal view returns (bool) {
        return (
            block.timestamp <= lottoIdToLotto[currentLottoId].startTime + expiry
                && lottoIdToLotto[currentLottoId].status != LotteryStatus.VRF_REQUESTED
                && lottoIdToLotto[currentLottoId].status != LotteryStatus.SETTLED
        );
    }

    function currentLottoEndable() internal view returns (bool) {
        return (
            block.timestamp >= lottoIdToLotto[currentLottoId].startTime + expiry
                && lottoIdToLotto[currentLottoId].status != LotteryStatus.SETTLED
                && lottoIdToLotto[currentLottoId].status != LotteryStatus.VRF_REQUESTED
        );
    }

    function newLottoStartable() internal view returns (bool) {
        return (lottoIdToLotto[currentLottoId].status == LotteryStatus.SETTLED);
    }

    function incrementNumberPos(uint256 pos, uint8 num) internal {
        lottoIdToPositionToNumberToCounter[currentLottoId][pos][num]++;
    }

    function getNumberCount(uint256 lottoId, uint256 pos, uint8 num) internal view returns (uint256) {
        return (lottoIdToPositionToNumberToCounter[lottoId][pos][num]);
    }

    function drawWinningNumbers(uint256 seed) internal pure returns (uint8[(5)] memory nums) {
        for (uint256 i = 0; i < 5; i++) {
            seed = uint256(keccak256(abi.encode(seed)));
            nums[i] = uint8(seed % 10);
        }
        return (nums);
    }

    function isValidNumbers(uint8[(5)] memory numbers) internal pure returns (bool) {
        for (uint256 i = 0; i < 5; i++) {
            if (numbers[i] > 9) {
                return (false);
            }
        }
        return (true);
    }

    function getWinningNumbers(uint256 lottoId) internal view returns (uint8[(5)] memory) {
        return (lottoIdToLotto[lottoId].winningNumbers);
    }

    function getTicketNumbers(uint256 ticketId) internal view returns (uint8[(5)] memory) {
        return (ticketIdToTicket[ticketId].numbers);
    }

    /**
     *  View functions
     *
     */

    function getLottoById(uint256 id)
        public
        view
        returns (
            uint256 startTime,
            uint256 prizePool,
            uint256 claimedAmount,
            uint256 seed,
            uint8[(5)] memory winningNumbers,
            LotteryStatus status
        )
    {
        return (
            lottoIdToLotto[id].startTime,
            lottoIdToLotto[id].prizePool,
            lottoIdToLotto[id].claimedAmount,
            lottoIdToLotto[id].seed,
            lottoIdToLotto[id].winningNumbers,
            lottoIdToLotto[id].status
        );
    }

    function getTicketById(uint256 id) public view returns (uint256 lottoId, uint8[(5)] memory numbers, bool claimed) {
        return (ticketIdToTicket[id].lottoId, ticketIdToTicket[id].numbers, ticketIdToTicket[id].claimed);
    }

    // Returns the number of tokens you would get per positional match. For example :
    // If winning numbers are [1,2,3,4,5], this function returns the prize return for matching per positon
    // say, 1 token for matching pos 1, 5 tokens for pos 2 etc.
    function getLottoPrize(uint256 lottoId) public view returns (uint256[(5)] memory prizeDistribution) {
        require(lottoIdToLotto[lottoId].status == LotteryStatus.SETTLED, "Requested Lottery instance is not settled");

        uint256 nc1 = getNumberCount(lottoId, 0, lottoIdToLotto[lottoId].winningNumbers[0]);
        uint256 nc2 = getNumberCount(lottoId, 1, lottoIdToLotto[lottoId].winningNumbers[1]);
        uint256 nc3 = getNumberCount(lottoId, 2, lottoIdToLotto[lottoId].winningNumbers[2]);
        uint256 nc4 = getNumberCount(lottoId, 3, lottoIdToLotto[lottoId].winningNumbers[3]);
        uint256 nc5 = getNumberCount(lottoId, 4, lottoIdToLotto[lottoId].winningNumbers[4]);

        return (
            [
                nc1 != 0 ? (lottoIdToLotto[lottoId].prizePool / 5) / nc1 : 0,
                nc2 != 0 ? (lottoIdToLotto[lottoId].prizePool / 5) / nc2 : 0,
                nc3 != 0 ? (lottoIdToLotto[lottoId].prizePool / 5) / nc3 : 0,
                nc4 != 0 ? (lottoIdToLotto[lottoId].prizePool / 5) / nc4 : 0,
                nc5 != 0 ? (lottoIdToLotto[lottoId].prizePool / 5) / nc5 : 0
            ]
        );
    }
}

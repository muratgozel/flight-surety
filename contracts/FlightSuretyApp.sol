// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./FlightSuretyData.sol";

contract FlightSuretyApp {
    using SafeMath for uint256;

    // flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    // we need multi-party consensus after this threshold
    uint8 private constant REQUIRE_CONSENSUS_THRESHOLD = 4;

    // percentage of registered airlines that should have been voted for an airline to be registered
    uint8 private constant SUCCESSFUL_CONSENSUS_THRESHOLD = 50;

    // airlines funded the contract with this amount can have a role
    uint private constant REQUIRED_FUNDING_AMOUNT = 20 ether;

    address private contractOwner;
    bool private registerAirlinesByConsensus;

    FlightSuretyData flightSuretyData;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }
    mapping(bytes32 => Flight) private flights;

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() {
        require(flightSuretyData.isOperational() == true, "Contract is currently not operational");
        _;
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireIsAirline() {
        require(flightSuretyData.isAirline(msg.sender) == true, "The sender address is not an airline.");
        _;
    }

    modifier requireIsMember() {
        require(flightSuretyData.isMember(msg.sender) == true, "Airline is not a member therefore can not perform this action.");
        _;
    }

    // it stores the data contract
    constructor(address payable flightSuretyDataContract) {
        contractOwner = msg.sender;
        registerAirlinesByConsensus = false;

        flightSuretyData = FlightSuretyData(flightSuretyDataContract);
    }

    // this is for testing operational status of the contract
    function setTestingMode(bool mode) requireIsOperational external view returns(bool) {
        return mode;
    }

    // registers airlines or their votes depending on the number of airlines currently registered
    function registerAirline(address airline)
        requireIsOperational
        requireIsAirline
        requireIsMember
        external
        returns(bool success, uint256 votes)
    {
        success = false;
        votes = 0;
        uint256 count = flightSuretyData.getNumberOfAirlines();
        if (count < REQUIRE_CONSENSUS_THRESHOLD) {
            flightSuretyData.insertAirline(airline);
            success = true;
        }
        else {
            votes = flightSuretyData.registerVote(airline);
            uint256 consensus = count.mul(SUCCESSFUL_CONSENSUS_THRESHOLD).div(100);

            if (votes >= consensus) {
                flightSuretyData.insertAirline(airline);
                success = true;
            }
        }
        return (success, votes);
    }

    // adds funds to an airline.
    // anyone can send funds and it can exceed REQUIRED_FUNDING_AMOUNT
    function fundAirline(address airline)
        requireIsOperational
        public
        payable
    {
        require(flightSuretyData.isAirline(airline) == true, "You are trying to fund a non-exist airline.");

        uint totalFundedSoFar = flightSuretyData.getAirlineFunds(airline);
        uint totalFundedNow = totalFundedSoFar.add(msg.value);
        flightSuretyData.updateAirlineFunds(airline, totalFundedNow, totalFundedNow >= REQUIRED_FUNDING_AMOUNT);

        payable(address(flightSuretyData)).transfer(msg.value);
    }

    // oracles

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        // Account that requested status
        address requester;
        // If open, oracle responses are accepted
        bool isOpen;
        // Mapping key is the status code reported.
        // This lets us group responses and identify the response that majority of the oracles
        mapping(uint8 => address[]) responses;
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);
    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);

    function registerOracle() external payable {
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(uint8 index, address airline, string flight, uint256 timestamp, uint8 statusCode) external {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");

        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);

        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }

    function getFlightKey(address airline, string flight, uint256 timestamp) pure internal returns(bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns(uint8[3]) {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    // functions for payments to work
    fallback() external payable {}
    receive() external payable {}
}

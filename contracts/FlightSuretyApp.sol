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
    uint8 public constant REQUIRE_CONSENSUS_THRESHOLD = 4;

    // percentage of registered airlines that should have been voted for an airline to be registered
    uint8 public constant SUCCESSFUL_CONSENSUS_THRESHOLD = 50;

    // airlines funded the contract with this amount can have a role
    uint public constant REQUIRED_FUNDING_AMOUNT = 20 ether;

    mapping(bytes32 => bool) private processedFlightStatus;

    address private contractOwner;
    bool private registerAirlinesByConsensus;

    FlightSuretyData flightSuretyData;

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

    modifier requireInputIsAirline(address airline) {
        require(flightSuretyData.isAirline(airline) == true, "No such airline registered in the system.");
        _;
    }

    modifier requireIsMember() {
        require(flightSuretyData.isMember(msg.sender) == true, "Airline is not a member therefore can not perform this action.");
        _;
    }

    modifier requireUniqueFlightNumber(bytes32 code) {
        require(code.length != 0, "Flight number can not be empty.");
        require(flightSuretyData.isFlightNumberUnique(code) == true, "A flight with this number already exists.");
        _;
    }

    modifier requireFlightExists(bytes32 code) {
        require(code.length != 0, "Flight number can not be empty.");
        require(flightSuretyData.isFlightNumberUnique(code) == false, "There is no flight with this number.");
        _;
    }

    modifier requireOracleRegistered() {
        require(oracles[msg.sender].isRegistered == true, "No such oracle found.");
        _;
    }

    modifier checkInsuranceAmount() {
        require(msg.value > 0 ether, "Insurance amount can not be empty.");
        require(msg.value <= 1 ether, "Insurance amount can't be higher than 1 ether.");
        _;
    }

    modifier requireCredit() {
        require(flightSuretyData.hasCredit(msg.sender) == true, "No credit found for this account.");
        _;
    }

    // it stores the data contract
    constructor(address payable flightSuretyDataContract) {
        contractOwner = msg.sender;
        registerAirlinesByConsensus = false;

        flightSuretyData = FlightSuretyData(flightSuretyDataContract);
    }

    function isOperational() public view returns(bool) {
        return flightSuretyData.isOperational() == true ? true : false;
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
            votes = flightSuretyData.registerVote(airline, msg.sender);
            uint256 consensus = count.mul(SUCCESSFUL_CONSENSUS_THRESHOLD).div(100);

            if (votes >= consensus) {
                flightSuretyData.insertAirline(airline);
                success = true;
            }
        }
        return (success, votes);
    }

    function getRegisteredAirlines() requireIsOperational external view returns(address[100] memory) {
        return flightSuretyData.getRegisteredAirlines();
    }

    function getMemberAirlines() requireIsOperational external view returns(address[100] memory) {
        return flightSuretyData.getMemberAirlines();
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

    function registerFlight(address airline, bytes32 code, uint256 departure)
        requireIsOperational
        requireIsAirline
        requireInputIsAirline(airline)
        requireUniqueFlightNumber(code)
        external
    {
        require(departure > block.timestamp == true, "Departure time should be a future date.");
        flightSuretyData.registerFlight(airline, code, departure, STATUS_CODE_UNKNOWN);
    }

    function getFlightNumbers() requireIsOperational external view returns(bytes32[100] memory) {
        return flightSuretyData.getFlightNumbers();
    }

    function processFlightStatus (address airline, bytes32 flight, uint256 timestamp, uint8 statusCode)
        requireIsOperational
        internal
    {
        if (statusCode == STATUS_CODE_LATE_AIRLINE && processedFlightStatus[flight] == false) {
            processedFlightStatus[flight] = true;
            flightSuretyData.creditInsuranceAmounts(flight);
        }
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus (bytes32 flight)
        requireIsOperational
        requireFlightExists(flight)
        external
    {
        uint256 timestamp = block.timestamp;
        address airline = flightSuretyData.getFlight(flight).airline;
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key].requester = msg.sender;
        oracleResponses[key].isOpen = true;

        emit OracleRequest(index, airline, flight, timestamp);
    }

    function buyInsurance(bytes32 flight)
        requireIsOperational
        requireFlightExists(flight)
        checkInsuranceAmount
        public
        payable
    {
        flightSuretyData.createInsurancePolicy(flight, msg.sender, msg.value);

        payable(address(flightSuretyData)).transfer(msg.value);
    }

    function withdraw()
        requireIsOperational
        requireCredit
        public
        payable
    {
        flightSuretyData.withdraw(msg.sender);
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
    event FlightStatusInfo(address airline, bytes32 flight, uint256 timestamp, uint8 status);
    event OracleReport(address airline, bytes32 flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, bytes32 flight, uint256 timestamp);

    function registerOracle() external payable {
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes()
        requireIsOperational
        requireOracleRegistered
        view
        external
        returns(uint8[3] memory)
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(uint8 index, address airline, bytes32 flight, uint256 timestamp, uint8 statusCode) external {
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

    function getFlightKey(address airline, bytes32 flight, uint256 timestamp) pure internal returns(bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns(uint8[3] memory) {
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

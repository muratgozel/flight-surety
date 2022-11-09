// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/*
    @title  This is the data contract of flight surety project.
*/
contract FlightSuretyData {
    using SafeMath for uint256;

    address private contractOwner;
    bool private operational;

    // keeping record of which contracts authorized to call this contract methods
    struct AuthorizedCaller {
        address caller;
        bool authorized;
    }
    mapping(address => AuthorizedCaller) private authorizedCallers;

    // registered, approved airlines
    struct Airline {
        address airline;
        uint totalFunded;
        bool member;
    }
    mapping(address => Airline) private airlines;
    // holds number of registered and member airlines
    uint256 private airlinesCount;
    uint256 private memberAirlinesCount;
    // we keep list of airlines for dapps and server apps
    address[100] private registeredAirlines;
    address[100] private memberAirlines;

    // record of voters based on airline
    struct Vote {
        address voter;
    }
    mapping(address => Vote[]) private votes;

    // records of flights
    struct Flight {
        uint8 statusCode;
        address airline;
        uint256 departure;
        bytes32 code;
        bool creditsDistributed;
    }
    mapping(bytes32 => Flight) private flights;
    bytes32[100] private flightNumbers;
    uint256 private flightsCount;

    // records of insurance policies
    struct Policy {
        address passenger;
        uint256 amount;
        bytes32 flight;
    }
    mapping(bytes32 => Policy[]) private insurances;

    // credit amounts in case of STATUS_CODE_LATE_AIRLINE
    mapping(address => uint256) private credits;

    modifier requireIsOperational() {
        require(operational == true, "Contract is currently not operational");
        _;
    }

    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireAuthorized() {
        require(authorizedCallers[msg.sender].authorized == true, "This is not an authorized call.");
        _;
    }

    modifier requireMembership(address airline) {
        require(airlines[airline].member == true, "The airline is registered but not a member.");
        _;
    }

    modifier preventDuplicates(address airline) {
        require(this.isAirline(airline) == false, "This airline already registered.");
        _;
    }

    modifier requireOneAirlineOneVote(address airline, address voter) {
        bool matched = false;
        if (votes[airline].length > 0) {
            for (uint i = 0; i < votes[airline].length; i++) {
                if (votes[airline][i].voter == voter) {
                    matched = true;
                }
            }
        }
        require(matched == false, "You already voted for this airline.");
        _;
    }

    modifier requireCreditsNotDistributed(bytes32 flight) {
        require(flights[flight].creditsDistributed == false, "Credits for this flight already distributed.");
        _;
    }

    constructor(address firstAirline) {
        contractOwner = msg.sender;
        operational = true;
        airlinesCount = 0;
        memberAirlinesCount = 0;
        flightsCount = 0;

        // contract owner also an authorized caller
        authorizedCallers[address(this)] = AuthorizedCaller({caller: address(this), authorized: true});
        // owner: accounts[0]
        authorizedCallers[msg.sender] = AuthorizedCaller({caller: msg.sender, authorized: true});

        _insertAirline(firstAirline);
    }

    function isOperational() public view returns(bool) {
        return operational;
    }

    function setOperatingStatus(bool mode)
        requireContractOwner
        public
        returns(bool)
    {
        operational = mode;
        return true;
    }

    function authorizeCaller(address caller)
        requireIsOperational
        requireContractOwner
        external
        returns(bool)
    {
        authorizedCallers[caller] = AuthorizedCaller({caller: caller, authorized: true});
        return true;
    }

    // checks if airline registered, doesn't take its membership into account
    function isAirline(address airline) requireAuthorized view external returns(bool) {
        return airlines[airline].airline != address(0) ? true : false;
    }

    // checks if airline is member
    function isMember(address airline) requireAuthorized requireMembership(airline) view external returns(bool) {
        return true;
    }

    function getNumberOfAirlines() requireAuthorized external view returns(uint) {
        return airlinesCount;
    }

    function _insertAirline(address airline) internal {
        airlinesCount = airlinesCount.add(1);
        registeredAirlines[ airlinesCount.sub(1) ] = airline;
        airlines[airline] = Airline({airline: airline, totalFunded: 0, member: false});
    }

    function insertAirline(address airline)
        requireIsOperational
        requireAuthorized
        preventDuplicates(airline)
        external returns(bool)
    {
        _insertAirline(airline);
        return true;
    }

    function registerVote(address airline, address voter)
        requireIsOperational
        requireAuthorized
        requireOneAirlineOneVote(airline, voter)
        external
        returns(uint256)
    {
        votes[airline].push( Vote({voter: voter}) );
        return votes[airline].length;
    }

    function getAirlineFunds(address airline)
        requireIsOperational
        requireAuthorized
        external
        view
        returns(uint)
    {
        return airlines[airline].totalFunded;
    }

    function updateAirlineFunds(address airline, uint total, bool becameMember)
        requireIsOperational
        requireAuthorized
        external
    {
        bool wasMember = airlines[airline].member;
        airlines[airline].totalFunded = total;
        airlines[airline].member = becameMember;

        if (wasMember == false && airlines[airline].member == true) {
            memberAirlinesCount = memberAirlinesCount.add(1);
            memberAirlines[ memberAirlinesCount.sub(1) ] = airline;
        }
    }

    function getRegisteredAirlines() requireIsOperational requireAuthorized external view returns(address[100] memory) {
        return registeredAirlines;
    }

    function getMemberAirlines() requireIsOperational requireAuthorized external view returns(address[100] memory) {
        return memberAirlines;
    }

    function isFlightNumberUnique(bytes32 code) external view returns(bool) {
        return flights[code].airline == address(0) ? true : false;
    }

    function registerFlight(address airline, bytes32 code, uint256 departure, uint8 statusCode)
        requireIsOperational
        requireAuthorized
        external
    {
        flightsCount = flightsCount.add(1);
        flightNumbers[ flightsCount.sub(1) ] = code;

        flights[code] = Flight({airline: airline, code: code, departure: departure, statusCode: statusCode, creditsDistributed: false});
    }

    function getFlight(bytes32 code) external view returns(Flight memory) {
        return flights[code];
    }

    function getFlightNumbers() external view returns(bytes32[100] memory) {
        return flightNumbers;
    }

    function createInsurancePolicy(bytes32 flight, address passenger, uint256 amount)
        requireIsOperational
        requireAuthorized
        external
    {
        insurances[flight].push( Policy({passenger: passenger, amount: amount, flight: flight}) );
    }

    function creditInsuranceAmounts(bytes32 flight)
        requireIsOperational
        requireAuthorized
        requireCreditsNotDistributed(flight)
        external
    {
        if (insurances[flight].length > 0) {
            for (uint i = 0; i < insurances[flight].length; i++) {
                credits[insurances[flight][i].passenger] = insurances[flight][i].amount.mul(3).div(2);
            }
            flights[flight].creditsDistributed = true;
        }
    }

    function hasCredit(address passenger) external view returns(bool) {
        return credits[passenger] == 0 ? false : true;
    }

    function getCreditAmount(address passenger) external view returns(uint256) {
        return credits[passenger];
    }

    function withdraw(address passenger) external payable {
        uint256 amount = credits[passenger];

        require(address(this).balance >= amount, "Contract has insufficient funds.");

        //delete credits[passenger];
        payable(passenger).transfer(amount);
    }

    receive() external payable {}
}
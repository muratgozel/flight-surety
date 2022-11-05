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

    // variable that holds number of registered airlines
    uint private airlinesCount;

    // registered, approved airlines
    struct Airline {
        address airline;
        uint totalFunded;
        bool member;
    }
    mapping(address => Airline) private airlines;

    // record of voters based on airline
    struct Vote {
        address voter;
    }
    mapping(address => Vote[]) private votes;

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

    modifier requireOneAirlineOneVote(address airline) {
        bool matched = false;
        if (votes[airline].length > 0) {
            for (uint i = 0; i < votes[airline].length; i++) {
                if (votes[airline][i].voter == tx.origin) {
                    matched = true;
                }
            }
        }
        require(matched == false, "You already voted for this airline.");
        _;
    }

    constructor(address firstAirline) {
        contractOwner = msg.sender;
        operational = true;
        airlinesCount = 0;

        // contract owner also an authorized caller
        authorizedCallers[address(this)] = AuthorizedCaller({caller: address(this), authorized: true});
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

    function registerVote(address airline)
        requireIsOperational
        requireAuthorized
        requireOneAirlineOneVote(airline)
        external
        returns(uint256)
    {
        votes[airline].push( Vote({voter: tx.origin}) );
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
        airlines[airline].totalFunded = total;
        airlines[airline].member = becameMember;
    }

    receive() external payable {}
}
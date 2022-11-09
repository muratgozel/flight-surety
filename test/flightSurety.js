const FlightSuretyApp = artifacts.require("FlightSuretyApp")
const FlightSuretyData = artifacts.require("FlightSuretyData")

async function configure(accounts) {
  const now = Math.floor(Date.now() / 1000)
  return {
    owner: accounts[0],
    firstAirline: accounts[1],
    flightSuretyData: await FlightSuretyData.deployed(),
    flightSuretyApp: await FlightSuretyApp.deployed(),
    oracles: accounts.slice(19, 39), // 20 oracles
    indexes: {},
    flightStatusCodes: [0, 10, 20, 30, 40, 50],
    flights: [ // these are pre-defined flights and registering a flight also possible from the dapp
      [accounts[1], 'UDA123', now + 300],
      [accounts[1], 'UDA456', now + 600],
      [accounts[2], 'ETH123', now + 300],
      [accounts[2], 'ETH456', now + 600]
    ]
  }
}

contract('Flight surety', async (accounts) => {
  let config = null;
  before('prepare', async () => {
    config = await configure(accounts)
  })

  it(`(multiparty) has correct initial isOperational() value`, async function () {
    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");
  })

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {
    // Ensure that access is denied for non-Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false, { from: accounts[2] });
    }
    catch(e) {
      accessDenied = true;
    }
    assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
  })

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {
    // Ensure that access is allowed for Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false);
    }
    catch(e) {
      accessDenied = true;
    }
    assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
  })

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {
    await config.flightSuretyData.setOperatingStatus(false);

    let reverted = false;
    try {
      await config.flightSurety.setTestingMode(true);
    }
    catch(e) {
      reverted = true;
    }
    assert.equal(reverted, true, "Access not blocked for requireIsOperational");

    // Set it back for other tests to work
    await config.flightSuretyData.setOperatingStatus(true);
  })

  it('(airline) first airline registered and funded on deploy.', async () => {
    let isAirline = false
    let isMember = false

    try {
      isAirline = await config.flightSuretyData.isAirline(config.firstAirline, {from: config.owner});
      isMember = await config.flightSuretyData.isMember(config.firstAirline, {from: config.owner});
    }
    catch (e) {}

    assert.equal(isAirline, true, "isAirline() should return true.")
    assert.equal(isMember, true, "isMember() should return true.")
  });

  it('(airline) can register (or vote) other airlines only if its a member, means funded.', async () => {
    let isAirline = false

    try {
      await config.flightSuretyApp.registerAirline(accounts[2], {from: config.firstAirline});
      isAirline = await config.flightSuretyData.isAirline(accounts[2], {from: config.owner});
    }
    catch (e) {}

    assert.equal(isAirline, true, "Second airline should be registered.")
  })

  it('(airline) can not register other airlines if it is not funded', async () => {
    let isAirline = false

    try {
      await config.flightSuretyApp.registerAirline(accounts[3], {from: accounts[2]});
      isAirline = await config.flightSuretyData.isAirline(accounts[3], {from: config.owner});
    }
    catch (e) {}

    assert.equal(isAirline, false, "Third airline shouldn't be registered at this point.");
  })

  it('(airline) must be funded at least with a certain amount to be a member', async () => {
    const requiredFundingAmount = await config.flightSuretyApp.REQUIRED_FUNDING_AMOUNT.call()
    let isMember = true

    // funding less than required amount
    await config.flightSuretyApp.fundAirline(accounts[2], {value: web3.utils.toWei("1", "wei")})
    try {
      isMember = await config.flightSuretyData.isMember(accounts[2], {from: config.owner});
    } catch (e) {
      isMember = false
    }
    assert.equal(isMember, false, "Airline shouldn't be a member at this point.")

    // funding more
    await config.flightSuretyApp.fundAirline(accounts[2], {value: requiredFundingAmount})
    try {
      isMember = await config.flightSuretyData.isMember(accounts[2], {from: config.owner});
    } catch (e) {
      isMember = false
    }
    assert.equal(isMember, true, "Airline should be a member at this point.")
  })

  it('(airline) data contract returns number of registered airlines', async () => {
    const count = await config.flightSuretyData.getNumberOfAirlines.call()

    assert.equal(count.toString(), '2', "There must be 2 airlines at this stage.")
  })

  it('(airline) can be registered directly by one of the member airlines until the 5th airline.', async () => {
    let isFifthRegistered = true
    const thirdAirline = accounts[3]
    const fourthAirline = accounts[4]
    const fifthAirline = accounts[5]

    await config.flightSuretyApp.registerAirline(thirdAirline, {from: config.firstAirline})
    await config.flightSuretyApp.registerAirline(fourthAirline, {from: config.firstAirline})
    await config.flightSuretyApp.registerAirline(fifthAirline, {from: config.firstAirline})

    try {
      isFifthRegistered = await config.flightSuretyData.isAirline.call(fifthAirline, {from: config.owner})
    }
    catch (e) {
      isFifthRegistered = false
    }

    assert.equal(isFifthRegistered, false, "Fifth airline can not be registered by one airline.")
  })

  it('(airline) 5th and subsequent airlines requires multi-party consensus to be registered.', async () => {
    const fifthAirline = accounts[5]

    await config.flightSuretyApp.registerAirline(fifthAirline, {from: accounts[2]})

    let isFifthRegistered = false
    try {
      isFifthRegistered = await config.flightSuretyData.isAirline.call(fifthAirline, {from: config.owner})
    }
    catch (e) {}

    assert.equal(isFifthRegistered, true, "Fifth airline should be registered when it got two votes.")
  })

  it('(airline) getRegisteredAirlines() returns list of registered airlines', async () => {
    const arr = await config.flightSuretyApp.getRegisteredAirlines()

    assert.equal(arr[0], accounts[1], "First airline must be in the list.")
    assert.equal(arr[1], accounts[2], "Second airline must be in the list.")
    assert.equal(arr[2], accounts[3], "Third airline must be in the list.")
    assert.equal(arr[3], accounts[4], "Fourth airline must be in the list.")
    assert.equal(arr[4], accounts[5], "Fifth airline must be in the list.")
  })

  it('(airline) getMemberAirlines() returns list of airlines funded enough to be a member', async () => {
    const arr = await config.flightSuretyApp.getMemberAirlines()

    assert.equal(arr[0], accounts[1], "First airline must be in member list.")
    assert.equal(arr[1], accounts[2], "Second airline must be in member list.")
  })

  it('(flight) can be registered', async () => {
    for (const flight of config.flights) {
      await config.flightSuretyApp.registerFlight(flight[0], web3.utils.asciiToHex(flight[1]), flight[2], {from: config.firstAirline})
    }

    const result = await config.flightSuretyData.getFlight.call(web3.utils.asciiToHex('UDA123'));
    assert.equal(web3.utils.hexToUtf8(result.code), 'UDA123', "Couldn't find flight.")

    const result2 = await config.flightSuretyData.getFlight.call(web3.utils.asciiToHex('INVALID'));
    assert.equal(web3.utils.hexToUtf8(result2.code), '', "Couldn't find flight.")
  })

  it('(flight) getFlightNumbers() returns list of flight numbers.', async () => {
    const arr = await config.flightSuretyApp.getFlightNumbers()

    assert.equal(web3.utils.hexToUtf8(arr[0]), config.flights[0][1], "First flight must be in the list.")
    assert.equal(web3.utils.hexToUtf8(arr[1]), config.flights[1][1], "Second flight must be in the list.")
    assert.equal(web3.utils.hexToUtf8(arr[2]), config.flights[2][1], "Third flight must be in the list.")
    assert.equal(web3.utils.hexToUtf8(arr[3]), config.flights[3][1], "Fourth flight must be in the list.")
  })

  it('(passenger) can buy insurance', async () => {
    const flight = web3.utils.asciiToHex(config.flights[0][1])
    const passenger = accounts[9]

    let error = false
    try {
      await config.flightSuretyApp.buyInsurance(flight, {from: passenger, value: web3.utils.toWei("0.1", "ether")})
    }
    catch (e) {
      console.error(e.message)
      error = true
    }

    assert.equal(error, false, "Passenger couldn't buy insurance for a flight.")
  })

  it('(oracle) can register oracles.', async () => {
    const count = []
    for (const oracle of config.oracles) {
      try {
        await config.flightSuretyApp.registerOracle({from: oracle, value: web3.utils.toWei("1", "ether")})
        count.push(oracle)
      }
      catch (e) {
        console.log(e.message)
      }

      const indexes = await config.flightSuretyApp.getMyIndexes.call({from: oracle})
      config.indexes[oracle] = indexes.map(item => parseInt(item))
    }

    assert.equal(count.length, config.oracles.length)
  })

  it('(oracle) submit a flight to oracles to check its reason for delay', async () => {
    const passenger = accounts[9]
    const flight = web3.utils.asciiToHex(config.flights[0][1])
    const result = await config.flightSuretyApp.fetchFlightStatus(flight)
    const eventName = result.logs[0].event

    assert.equal(eventName, 'OracleRequest', "Oracle event didn't get triggered.")

    const index = result.logs[0].args.index.toNumber()
    const airline = result.logs[0].args.airline
    const timestamp = result.logs[0].args.timestamp.toNumber()
    const matches = []
    for (const oracle of config.oracles) {
      if (config.indexes[oracle].indexOf(parseInt(index)) === -1) continue;
      const selection = 20 // Math.floor(Math.random() * config.flightStatusCodes.length)
      matches.push(selection)
      const r = await config.flightSuretyApp.submitOracleResponse(index, airline, flight, timestamp, web3.utils.toBN(selection), {from: oracle})
    }
    assert.equal(matches.length > 0, true, "Couldn't found corresponding oracle for the index.")

    const has = await config.flightSuretyData.hasCredit(passenger)
    assert.equal(has, true, "Passenger doesn't have any credit.")
  })

  it('(oracle) credits the passengers for withdraw', async () => {
    const passenger = accounts[9]
    const flight = web3.utils.asciiToHex(config.flights[0][1])

    const bn = await config.flightSuretyData.getCreditAmount(passenger)

    assert.equal(bn.toString(), web3.utils.toWei('0.15', 'ether'), "Credit amount for the passenger looks wrong.")
  })

  it('(passenger) can withdraw their credited amount.', async () => {
    const passenger = accounts[9]

    let error = true
    try {
      await config.flightSuretyApp.withdraw({from: passenger})
      error = false
    }
    catch (e) {
      console.error(e.message)
    }

    assert.equal(error, false, "Couldn't withdraw funds to passenger.")
  })
})
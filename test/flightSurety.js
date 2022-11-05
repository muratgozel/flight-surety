const BigNumber = require('bignumber.js')

const FlightSuretyApp = artifacts.require("FlightSuretyApp")
const FlightSuretyData = artifacts.require("FlightSuretyData")

async function configure(accounts) {
  return {
    owner: accounts[0],
    firstAirline: accounts[1],
    weiMultiple: (new BigNumber(10)).pow(18),
    flightSuretyData: await FlightSuretyData.deployed(),
    flightSuretyApp: await FlightSuretyApp.deployed()
  }
}

contract('Flight surety', async (accounts) => {
  let config = null;
  before('prepare', async () => {
    config = await configure(accounts)
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address)
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

  it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {
    let newAirline = accounts[2];

    try {
      await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
    }
    catch (e) {}
    let result = await config.flightSuretyData.isAirline.call(newAirline);

    assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");
  })

  it('(airline) must be funded at least with a certain amount to be a member', async () => {
    const someAddressWithEther = accounts[40]
    let isMember = null

    // funding less than required amount
    await config.flightSuretyApp.fundAirline(config.firstAirline, {value: web3.utils.toWei("1", "ether")})
    try {
      isMember = await config.flightSuretyData.isMember.call(config.firstAirline)
    } catch (e) {
      isMember = false
    }
    assert.equal(isMember, false, "Airline shouldn't participate to contract when it got small amount of funding.")

    // funding more
    await config.flightSuretyApp.fundAirline(config.firstAirline, {value: web3.utils.toWei("19", "ether")})
    isMember = await config.flightSuretyData.isMember.call(config.firstAirline)
    assert.equal(isMember, true, "Airline should participate to contract once it has enough amount of funding.")
  })

  it('(airline) can only register another airline if its funded enough', async () => {
    let isRegistered = false
    const secondAirline = accounts[2]
    await config.flightSuretyApp.registerAirline(secondAirline, {from: config.firstAirline})

    try {
      isRegistered = await config.flightSuretyData.isAirline.call(secondAirline)
    }
    catch (e) {
      isRegistered = false
    }

    assert.equal(isRegistered, true, "Member airlines can register other airlines.")
  })

  it('(airline) data contract returns number of registered airlines', async () => {
    const count = await config.flightSuretyData.getNumberOfAirlines.call()

    assert.equal(count.toString(), '2', "There must be 2 airlines at this stage.")
  })

  it('(airline) can register four airlines at most by itself.', async () => {
    let isFifthRegistered = null
    const thirdAirline = accounts[3]
    const fourthAirline = accounts[4]
    const fifthAirline = accounts[5]

    await config.flightSuretyApp.registerAirline(thirdAirline, {from: config.firstAirline})
    await config.flightSuretyApp.registerAirline(fourthAirline, {from: config.firstAirline})
    await config.flightSuretyApp.registerAirline(fifthAirline, {from: config.firstAirline})

    try {
      isFifthRegistered = await config.flightSuretyData.isAirline.call(fifthAirline)
    }
    catch (e) {}

    assert.equal(isFifthRegistered, false, "Fifth airline can not be registered directly.")
  })

  it('(airline) it requires at least 2 registerAirline() call for fifth airline to be registered', async () => {
    let isFifthRegistered = null
    const secondAirline = accounts[2]
    const fifthAirline = accounts[5]

    await config.flightSuretyApp.fundAirline(secondAirline, {value: web3.utils.toWei("20", "ether")})
    await config.flightSuretyApp.registerAirline(fifthAirline, {from: secondAirline})

    try {
      isFifthRegistered = await config.flightSuretyData.isAirline.call(fifthAirline)
    }
    catch (e) {
      isFifthRegistered = false
    }

    assert.equal(isFifthRegistered, true, "Fifth airline can be registered when it got two votes.")
  })
})
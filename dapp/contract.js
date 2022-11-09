import FlightSuretyApp from '../build/contracts/FlightSuretyApp.json';
import Web3 from "web3";

export default class Contract {
  accounts = []
  owner = null
  airlines = []
  passengers = []
  flights = []

  constructor({config}) {
    this.web3 = new Web3(new Web3.providers.HttpProvider(config.url))
    this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress)
  }

  async init() {
    this.accounts = await this.web3.eth.getAccounts()
    this.owner = this.accounts[0]
    this.airlines = await this.getRegisteredAirlines()
    this.memberAirlines = await this.getMemberAirlines()
    this.passengers = this.accounts.slice(9, 14)
    this.flights = await this.getFlights()
  }

  async isOperational() {
    return await this.flightSuretyApp.methods.isOperational().call({from: this.owner})
  }

  async getRegisteredAirlines() {
    const arr = await this.flightSuretyApp.methods.getRegisteredAirlines().call({from: this.owner})
    return arr.filter(addr => /^0x0+$/.test(addr) === false)
  }

  async getMemberAirlines() {
    const arr = await this.flightSuretyApp.methods.getMemberAirlines().call({from: this.owner})
    return arr.filter(addr => /^0x0+$/.test(addr) === false)
  }

  async getFlights() {
    const arr = await this.flightSuretyApp.methods.getFlightNumbers().call({from: this.owner})
    return arr.filter(addr => /^0x0+$/.test(addr) === false).map(code => this.web3.utils.hexToUtf8(code))
  }

  async registerAirline(airline, from) {
    try {
      return await this.flightSuretyApp.methods.registerAirline(airline).send({from: from, gas: 1000000})
    }
    catch (e) {
      return e
    }
  }

  async registerFlight(airline, code, departure, from) {
    try {
      return await this.flightSuretyApp.methods
        .registerFlight(airline, this.web3.utils.asciiToHex(code), departure)
        .send({from: from, gas: 1000000})
    }
    catch (e) {
      return e
    }
  }

  async fetchFlightStatus(code) {
    try {
      return await this.flightSuretyApp.methods
        .fetchFlightStatus(this.web3.utils.asciiToHex(code))
        .send({from: this.owner, gas: 1000000})
    }
    catch (e) {
      return e
    }
  }

  async buyInsurance(code, amount, passenger) {
    try {
      return await this.flightSuretyApp.methods
        .buyInsurance(this.web3.utils.asciiToHex(code))
        .send({from: passenger, value: this.web3.utils.toWei(amount.toString(), "ether"), gas: 1000000})
    }
    catch (e) {
      return e
    }
  }

  async withdraw(from) {
    try {
      return await this.flightSuretyApp.methods.withdraw().send({from: from, gas: 1000000})
    }
    catch (e) {
      return e
    }
  }
}
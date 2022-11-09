import {setTimeout} from "node:timers/promises";
import Web3 from "web3";

export default class Contract {
  accounts = []
  owner = null
  oracles = []
  indexes = {}
  flightStatusCodes = [0, 10, 20, 30, 40, 50]

  constructor({config, app}) {
    this.web3 = new Web3( new Web3.providers.WebsocketProvider(config.url.replace('http', 'ws')) )
    this.flightSuretyApp = new this.web3.eth.Contract(app.abi, config.appAddress)
  }

  async init() {
    this.accounts = await this.web3.eth.getAccounts()
    this.owner = this.accounts[0]
    this.oracles = this.accounts.slice(19, 39) // 20 oracles

    await this.createOracles()
  }

  async createOracles() {
    // it is weird that .call() needs to be called twice
    const fee = await this.flightSuretyApp.methods.REGISTRATION_FEE.call().call()
    for (const oracle of this.oracles) {
      try {
        await this.flightSuretyApp.methods.registerOracle().send({from: oracle, value: fee, gas: 1000000})

        try {
          const indexes = await this.flightSuretyApp.methods.getMyIndexes().call({from: oracle})
          this.indexes[oracle] = indexes.map(item => parseInt(item))

          console.log(`Successfully registered oracle ${oracle.toString().slice(0, 6)}`)
        }
        catch (e) {
          console.log(`Failed to getMyIndexes() for an oracle ${oracle.toString().slice(0, 6)}: ${e.message}`)
        }
      }
      catch (e) {
        console.log(`Failed to register the oracle ${oracle.toString().slice(0, 6)}: ${e.message}`)
      }
    }
  }

  async checkFlightStatus(index, airline, flight, timestamp) {
    const responses = []
    for (const oracle of this.oracles) {
      if (this.indexes[oracle].indexOf(parseInt(index)) === -1) continue;
      const selection = Math.floor(Math.random() * this.flightStatusCodes.length)
      responses.push({oracle, status: this.flightStatusCodes[selection]})
    }
    return responses
  }
}
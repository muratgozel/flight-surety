import {readFile} from "node:fs/promises";
import Contract from "./contract.js";

const config = JSON.parse(await readFile('./server/config.json', 'utf8'))
const FlightSuretyApp = JSON.parse(await readFile('./build/contracts/FlightSuretyApp.json', 'utf8'))

const contract = new Contract({config: config.localhost, app: FlightSuretyApp})
await contract.init()

contract.flightSuretyApp.events.OracleRequest({fromBlock: 0}, async function (error, event) {
  if (error) console.log(error)

  if (event.event === 'OracleRequest') {
    const index = ~~event.returnValues.index
    const airline = event.returnValues.airline
    const flight = event.returnValues.flight
    const timestamp = ~~event.returnValues.timestamp
    const responses = await contract.checkFlightStatus(index, airline, flight, timestamp)

    for (const response of responses) {
      try {
        await contract.flightSuretyApp.methods
          .submitOracleResponse(index, airline, flight, timestamp, contract.web3.eth.abi.encodeParameter('uint8', response.status.toString()))
          .send({from: response.oracle, gas: 1000000})
        console.log(`Oracle response submitted with status ${response.status}`)
      }
      catch (e) {
        console.log(e.message)
      }
    }
  }
})

contract.flightSuretyApp.events.FlightStatusInfo({fromBlock: 0}, async function(error, event) {
  if (event.event === 'FlightStatusInfo') {
    const flight = contract.web3.utils.hexToUtf8(event.returnValues.flight)
    console.log(`FlightStatusInfo: ${flight} is ${event.returnValues.status}`)
  }
})

contract.web3.eth.subscribe('logs').on('data', (data) => console.log(data))
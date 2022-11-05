const FlightSuretyApp = artifacts.require("FlightSuretyApp");
const FlightSuretyData = artifacts.require("FlightSuretyData");
const fs = require('fs');

module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(FlightSuretyData, accounts[1])
    await deployer.deploy(FlightSuretyApp, FlightSuretyData.address)

    const config = {
        localhost: {
            url: 'http://127.0.0.1:8545',
            dataAddress: FlightSuretyData.address,
            appAddress: FlightSuretyApp.address
        }
    }
    const configstr = JSON.stringify(config, null, '\t')
    fs.writeFileSync(__dirname + '/../dapp/config.json', configstr, 'utf-8');
    fs.writeFileSync(__dirname + '/../server/config.json', configstr, 'utf-8');
}
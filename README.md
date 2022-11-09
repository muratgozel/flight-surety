# Flight Surety
Final project of Udacity Blockchain Developer Nanodegree program, flight delay insurance application based on smart contracts run on blockchain.

## Setup
1. Ganache
2. node.js
3. Clone this repository with `git clone https://github.com/muratgozel/flight-surety.git`
4. Run `npm install`
5. Run `npm run compile`

## Initial Configuration
1. Create a local blockchain with Ganache. Have at least 100 accounts, 1000 ether for each and use the mnemonic inside `truffle-config.js` file.
2. Run `npm run migrate`. This will deploy your contracts on the local blockchain.
3. Run `npm run dapp` to launch the web app. It will be available at http://127.0.0.1:8000
4. Run `npm run server` to launch the server.

## Run Tests
The project has an automated test suite inside test folder and the dapp can be used to test its functionality. To use the test suite, run `npm run test` and to use the dapp just go to http://127.0.0.1:8000.

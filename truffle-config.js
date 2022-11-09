const HDWalletProvider = require('@truffle/hdwallet-provider')

const mnemonic = 'mother electric dynamic desert verb kit chimney close tumble ladder try bubble'

module.exports = {
  networks: {
    development: {
      provider: function () {
        return new HDWalletProvider({
          mnemonic: mnemonic,
          providerOrUrl: "http://127.0.0.1:8545",
          numberOfAddresses: 50
        })
      },
      network_id: "*" // Match any network id
    }
  },
  compilers: {
    solc: {
      version: "0.8.0",
      settings: {
        optimizer: {
          enabled: true,
          runs: 100
        }
      }
    }
  }
}
require('dotenv').config();
const HDWalletProvider = require('@truffle/hdwallet-provider');

const RinkebyProvider = new HDWalletProvider(process.env['RINKEBY_PRIVATE_KEY'], 'wss://rinkeby.infura.io/ws/v3/e69a285bfdc34992a32fa06dd4743923');
const GoerliProvider = new HDWalletProvider(process.env['RINKEBY_PRIVATE_KEY'], 'wss://goerli.infura.io/ws/v3/e69a285bfdc34992a32fa06dd4743923');

module.exports = {
  api_keys: {
    etherscan: process.env['ETHERSCAN_API_KEY']
  },
  plugins: [
    'truffle-plugin-verify'
  ],
  mocha: {
    timeout: 100000
  },
  compilers: {
    solc: {
      version: "0.8.7",
      settings: {
        optimizer: {
          enabled: true,
          runs: 2000
        }
      }
    },
  },
  networks: {
    development: {
      host: "localhost",
      port: 7545,
      network_id: "*"
    },
    rinkeby: {
      provider: RinkebyProvider,
      network_id: '4',
      skipDryRun: true,
      gasPrice: 3000000000
    },
    goerli: {
      provider: GoerliProvider,
      network_id: '5',
      skipDryRun: true,
      gasPrice: 3000000000
    },
  }
};

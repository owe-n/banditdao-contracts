/**
 * @type import('hardhat/config').HardhatUserConfig
 */

require('dotenv').config()
require('@nomiclabs/hardhat-ethers')
require('@nomiclabs/hardhat-solhint')
require('@nomiclabs/hardhat-waffle')
require('@nomiclabs/hardhat-web3')
require('hardhat-abi-exporter')
require('hardhat-gas-reporter')
require('hardhat-watcher')
require('solidity-coverage')

module.exports = {
  solidity: {
    version: '0.8.10',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
}

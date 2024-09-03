require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config();
require('./scripts/tasks');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  sourcify: {
    enabled: false
  },
  etherscan: {
    apiKey: {
      testnet: "ixRghuroxbZ4Xi7mA393",
      mainnet: "ixRghuroxbZ4Xi7mA393"
    },
    customChains: [
      {
        network: "testnet",
        chainId: 14333,
        urls: {
          apiURL: "https://test-explorer.vitruveo.xyz/api",
          browserURL: "https://www.vitruveo.xyz",
        }
      },
      {
        network: "mainnet",
        chainId: 1490,
        ensAddress: null,
        urls: {
          apiURL: "https://explorer.vitruveo.xyz/api",
          browserURL: "https://www.vitruveo.xyz",
        }
      }

    ]

  },
  networks: {
    testnet: {
      url: "https://test-rpc.vitruveo.xyz",
      accounts: [
                  process.env.DEPLOYER_PRIVATE_KEY,
                  process.env.SWAP1_PRIVATE_KEY,
                  process.env.SWAP2_PRIVATE_KEY,
                  process.env.SWAP3_PRIVATE_KEY,
                  process.env.SWAP4_PRIVATE_KEY,
                ]  
    },
    local: {
      url: "http://localhost:8545",
      accounts: [
                  process.env.DEPLOYER_PRIVATE_KEY,
                  process.env.SWAP1_PRIVATE_KEY,
                  process.env.SWAP2_PRIVATE_KEY,
                  process.env.SWAP3_PRIVATE_KEY,
                  process.env.SWAP4_PRIVATE_KEY,
                ]  
    },
    mainnet: {
      url: "https://rpc.vitruveo.xyz",
      accounts: [
                  process.env.DEPLOYER_PRIVATE_KEY,
                  process.env.SWAP1_PRIVATE_KEY,
                  process.env.SWAP2_PRIVATE_KEY,
                  process.env.SWAP3_PRIVATE_KEY,
                  process.env.SWAP4_PRIVATE_KEY,
                ]  
    }
  }
};

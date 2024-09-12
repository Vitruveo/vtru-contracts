require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config();
require('./scripts/tasks');

const accounts = [
  process.env.DEPLOYER_PRIVATE_KEY,
  process.env.SWAP1_PRIVATE_KEY,
  process.env.SWAP2_PRIVATE_KEY,
  process.env.SWAP3_PRIVATE_KEY,
  process.env.SWAP4_PRIVATE_KEY,
]

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  gasPrice: 10000000000,
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
      mainnet: "ixRghuroxbZ4Xi7mA393",
      ethereum: "B6WYP17AK8VV97HGGZY89WMFU71A1RXQJP",
      bsc: "DRYMTWJUZSZM3E9V95GKKNHGZH5SK7TR6F",
      polygon: "VD2JW4YQ8UHBU6U9UPMA2DUXM1XMG4FHE1",
      base: "CCR53NRFN3G4WJMM5TA3FUD3GXP73ASIG9",
      avalanche: "0"
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
      accounts: accounts  
    },
    local: {
      url: "http://localhost:8545",
      accounts: accounts  
    },
    mainnet: {
      url: "https://rpc.vitruveo.xyz",
      accounts: accounts  
    },
    ethereum: {
      url: "https://eth-mainnet.nodereal.io/v1/a54fef697b604ae3af38fe5cc2d7da0f",
      accounts: accounts
    },
    base: {
      url: "https://open-platform.nodereal.io/a54fef697b604ae3af38fe5cc2d7da0f/base",
      accounts: accounts
    },
    bsc: {
      url: "https://bsc-mainnet.nodereal.io/v1/a54fef697b604ae3af38fe5cc2d7da0f",
      accounts: accounts
    },
    polygon: {
      url: "https://polygon-mainnet.nodereal.io/v1/a54fef697b604ae3af38fe5cc2d7da0f",
      accounts: accounts
    },
    avalanche: {
      url: "https://open-platform.nodereal.io/a54fef697b604ae3af38fe5cc2d7da0f/avalanche-c/ext/bc/C/rpc",
      accounts: accounts
    }
  }
};

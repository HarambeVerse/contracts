// eslint-disable import/no-extraneous-dependencies
import { task } from 'hardhat/config';
import 'hardhat-contract-sizer';
import { config as dotenvConfig } from 'dotenv';

import { resolve } from 'path';

import { HardhatUserConfig } from 'hardhat/types';

import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-gas-reporter';
import '@nomiclabs/hardhat-etherscan';
import { accounts } from './test-accounts';

dotenvConfig({ path: resolve(__dirname, './.env') });

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

const MNEMONIC = process.env.MNEMONIC || '';
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || '';
const INFURA_API_KEY = process.env.INFURA_API_KEY || '';

function createTestnetConfig(network: keyof typeof chainIds) {
  const url = `https://${network}.infura.io/v3/${INFURA_API_KEY}`;
  return {
    accounts: {
      count: 10,
      initialIndex: 0,
      mnemonic: MNEMONIC,
      path: "m/44'/60'/0'/0",
    },
    chainId: chainIds[network],
    url,
  };
}

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 200,
    // enabled: process.env.REPORT_GAS ? true : false,
  },
  networks: {
    goerli: createTestnetConfig('goerli'),
    hardhat: {
      accounts,
      chainId: chainIds.hardhat,
    },
    kovan: createTestnetConfig('kovan'),
    mainnet: createTestnetConfig('mainnet'),
    matic: {
      accounts: {
        count: 10,
        initialIndex: 0,
        mnemonic: MNEMONIC,
        path: "m/44'/60'/0'/0",
      },
      url: 'https://rpc-mainnet.maticvigil.com/v1/476abba7bd6ae0c950a9880685600bace7e89ee9',
    },
    rinkeby: {
      ...createTestnetConfig('rinkeby'),
      gas: 2100000,
      gasPrice: 8000000000,
    },
    ropsten: createTestnetConfig('ropsten'),
  },
  solidity: {
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
    version: '0.8.4',
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
};

export default config;

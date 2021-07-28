# Harambe Verse Contracts

Contracts for Harambe Verse

##### Duck address: [0x91B0D8beEa83cc9F7170b83E94B3a294e8e2ee59](https://polygonscan.com/address/0x91B0D8beEa83cc9F7170b83E94B3a294e8e2ee59)

## Usage

### Pre Requisites

Before running any command, make sure to install dependencies:

```sh
$ npm install
```

### Compile

Compile the smart contracts with Hardhat:

```sh
$ npm run compile
```

### Test

Run the Mocha tests:

```sh
$ npm run test
```

### Deploy contract to netowrk (requires Mnemonic and infura API key)

```
npx hardhat run --network rinkeby ./scripts/deploy.ts
```

### Validate a contract with etherscan (requires API ke)

```
npx hardhat verify --network <network> <DEPLOYED_CONTRACT_ADDRESS> "Constructor argument 1"
```

### Added plugins

- Gas reporter [hardhat-gas-reporter](https://hardhat.org/plugins/hardhat-gas-reporter.html)
- Etherscan [hardhat-etherscan](https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html)

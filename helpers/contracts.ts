import { ethers, network } from 'hardhat';
import { Contract, ContractTransaction } from 'ethers';
import low from 'lowdb';
import FileSync from 'lowdb/adapters/FileSync';

import { ContractId } from '../enums/Contract';
import {
  Duck,
  DuckMinter,
} from '../typechain';

export const getDb = () => low(new FileSync('./deployed-contracts.json'));
export const waitForTx = async (tx: ContractTransaction) => tx.wait();

export const getContract = async <IContract extends Contract>(
  contractName: string,
  address: string,
): Promise<IContract> =>
  (await ethers.getContractAt(contractName, address)) as IContract;

export const getDuckToken = async (address?: string) => {
  return getContract<Duck>(
    ContractId.Duck,
    address ||
      (await getDb().get(`${ContractId.Duck}.${network.name}`).value()).address,
  );
};

export const registerContractInJsonDb = async (
  contractId: string,
  contractInstance: Contract,
) => {
  const currentNetwork = network.name;

  if (currentNetwork !== 'hardhat' && currentNetwork !== 'coverage') {
    console.info(`\n\t  *** ${contractId} ***\n`);
    console.info(`\t  Network: ${currentNetwork}`);
    console.info(`\t  tx: ${contractInstance.deployTransaction.hash}`);
    console.info(`\t  contract address: ${contractInstance.address}`);

    console.info(
      `\t  deployer address: ${contractInstance.deployTransaction.from}`,
    );

    console.info(
      `\t  gas price: ${contractInstance.deployTransaction.gasPrice}`,
    );

    console.info(
      `\t  gas used: ${contractInstance.deployTransaction.gasLimit}`,
    );

    console.info(`\t  ******`);
  }

  await getDb()
    .set(`${contractId}.${currentNetwork}`, {
      address: contractInstance.address,
      deployer: contractInstance.deployTransaction.from,
    })
    .write();
};

const createContractInstance = async <IContract extends Contract>(
  contractName: string,
  args: any[],
): Promise<IContract> => {
  const contract = (await (
    await ethers.getContractFactory(contractName)
  ).deploy(...args)) as IContract;

  await waitForTx(contract.deployTransaction);
  await registerContractInJsonDb(<ContractId>contractName, contract);
  return contract;
};

const deployContract = async <IContract extends Contract, IArgs extends any[]>(
  id: ContractId,
  args: IArgs,
) => {
  const instance = await createContractInstance<IContract>(id, args);
  await instance.deployTransaction.wait();
  return instance;
};

export const deployDuck = async () =>
  deployContract<Duck, string[]>(ContractId.Duck, []);

export const deployDuckMinter = async (address: string) =>
  deployContract<DuckMinter, string[]>(ContractId.DuckMinter, [address]);

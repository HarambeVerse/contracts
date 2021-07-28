// eslint-disable-next-line import/no-extraneous-dependencies
import { ethers } from 'hardhat';

import { Duck__factory } from '../typechain';

(async () => {
  const [signer] = await ethers.getSigners();
  const DuckFactory = new Duck__factory(signer);

  const duck = await DuckFactory.deploy(
    '0x16a4c8Ac5086Bc1428fb9c2681E2E10ab89f4625',
  );

  await duck.deployed();

  console.info(`Duck deployed at address ${duck.address}`);
})();

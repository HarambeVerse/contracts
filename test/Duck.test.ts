import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import chai from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { Duck, Duck__factory } from '../typechain';

const { expect } = chai;

describe('Duck token', () => {
  const name = 'Duck';
  const symbol = 'DUCK';
  let signer1: SignerWithAddress;
  let signer2: SignerWithAddress;
  let signer3: SignerWithAddress;
  let DuckFactory: Duck__factory;
  let duck: Duck;

  before(async () => {
    [signer1, signer2, signer3] = await ethers.getSigners();
    DuckFactory = new Duck__factory(signer1);
  });

  beforeEach(async () => {
    duck = await DuckFactory.deploy();
    await duck.deployed();
  });

  describe('metadata', () => {
    it('has given name', async () => {
      expect(await duck.name()).to.eq(name);
    });

    it('has given symbol', async () => {
      expect(await duck.symbol()).to.eq(symbol);
    });
  });

  describe('delegateBySig', () => {
    it('reverts if the signatory is invalid', async () => {
      const delegatee = signer1.address;
      const nonce = BigNumber.from(0);
      const expiry = BigNumber.from(0);

      await expect(
        duck.delegateBySig(
          delegatee,
          nonce,
          expiry,
          0,
          '0xc7826f1fe753c62a24cc021b35c222e29f1931dbdfe14bcce011fd7b9d213f6f',
          '0xc7826f1fe753c62a24cc021b35c222e29f1931dbdfe14bcce011fd7b9d213f6f',
        ),
      ).to.be.revertedWith('DUCK: delegateBySig: invalid signature');
    });
  });
});

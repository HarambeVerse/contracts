import { ethers } from 'hardhat';
import { BigNumber, Wallet } from 'ethers';
import chai from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ecsign } from 'ethereumjs-util';

import { Duck, Duck__factory } from '../typechain';

import { ADDRESS_ZERO, getDelegateDigest } from './utils';

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

    it('reverts if the nonce is bad', async () => {
      const wallet = Wallet.createRandom();
      const delegatee = signer1.address;
      const nonce = BigNumber.from(1);
      const expiry = BigNumber.from(10e9);

      const digest = await getDelegateDigest(
        duck,
        { delegatee, expiry },
        nonce,
      );

      const { r, s, v } = ecsign(
        Buffer.from(digest.slice(2), 'hex'),
        Buffer.from(wallet.privateKey.slice(2), 'hex'),
      );

      await expect(
        duck.delegateBySig(delegatee, nonce, expiry, v, r, s),
      ).to.be.revertedWith('DUCK: delegateBySig: invalid nonce');
    });

    it('reverts if the signature has expired', async () => {
      const wallet = Wallet.createRandom();
      const delegatee = signer1.address;
      const nonce = BigNumber.from(0);
      const expiry = BigNumber.from(0);

      const digest = await getDelegateDigest(
        duck,
        { delegatee, expiry },
        nonce,
      );

      const { r, s, v } = ecsign(
        Buffer.from(digest.slice(2), 'hex'),
        Buffer.from(wallet.privateKey.slice(2), 'hex'),
      );

      await expect(
        duck.delegateBySig(delegatee, nonce, expiry, v, r, s),
      ).to.be.revertedWith('DUCK: delegateBySig: signature expired');
    });

    it('delegates on behalf of the signatory', async () => {
      const wallet = Wallet.createRandom();
      const delegatee = signer1.address;
      const nonce = BigNumber.from(0);
      const expiry = BigNumber.from(10e9);

      const digest = await getDelegateDigest(
        duck,
        { delegatee, expiry },
        nonce,
      );

      const { r, s, v } = ecsign(
        Buffer.from(digest.slice(2), 'hex'),
        Buffer.from(wallet.privateKey.slice(2), 'hex'),
      );

      expect(await duck.delegates(wallet.address)).to.eq(ADDRESS_ZERO);

      const tx = await duck.delegateBySig(delegatee, nonce, expiry, v, r, s);

      await tx.wait();

      /// @todo wallet address is different than when ECDSASignature
      expect(await duck.delegates(wallet.address)).to.eq(signer1.address);
    });
  });
});

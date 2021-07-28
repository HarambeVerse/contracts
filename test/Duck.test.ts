import { ethers, network } from 'hardhat';
import { BigNumber } from 'ethers';
import chai from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ecsign } from 'ethereumjs-util';
import { TypedData } from 'eth-sig-util';

import { Duck, Duck__factory } from '../typechain';
import { accounts } from '../test-accounts';

import { buildDelegateParams, getSignatureFromTypedData } from './utils';

const { expect } = chai;

describe('Duck token', () => {
  const name = 'Duck';
  const symbol = 'DUCK';
  let signer1: SignerWithAddress;
  let signer2: SignerWithAddress;
  let signer3: SignerWithAddress;
  let signer4: SignerWithAddress;
  let DuckFactory: Duck__factory;
  let duck: Duck;

  before(async () => {
    [signer1, signer2, signer3, signer4] = await ethers.getSigners();
    DuckFactory = new Duck__factory(signer1);
  });

  beforeEach(async () => {
    duck = await DuckFactory.deploy(signer1.address);

    await duck.deployed();
    duck.setupMinter(signer1.address);
  });

  describe('metadata', () => {
    it('has given name', async () => {
      expect(await duck.name()).to.eq(name);
    });

    it('has given symbol', async () => {
      expect(await duck.symbol()).to.eq(symbol);
    });
  });

  describe('token', () => {
    it('should only allow owner to mint token', async () => {
      await duck.mint(signer2.address, '100');
      await duck.mint(signer3.address, '1000');

      await expect(
        duck
          .connect(signer3)
          .mint(signer4.address, '1000', { from: signer3.address }),
      ).to.be.revertedWith('DuckAccessControl: Only minter');

      const totalSupply = await duck.totalSupply();
      const aliceBal = await duck.balanceOf(signer2.address);
      const bobBal = await duck.balanceOf(signer3.address);
      const carolBal = await duck.balanceOf(signer4.address);
      expect(totalSupply).to.equal('50010000000000000001100');
      expect(aliceBal).to.equal('100');
      expect(bobBal).to.equal('1000');
      expect(carolBal).to.equal('0');
    });

    it('should supply token transfers properly', async () => {
      await duck.mint(signer2.address, '100');
      await duck.mint(signer3.address, '1000');
      await duck.transfer(signer4.address, '10');

      await duck.connect(signer3).transfer(signer4.address, '100', {
        from: signer3.address,
      });

      const totalSupply = await duck.totalSupply();
      const aliceBal = await duck.balanceOf(signer2.address);
      const bobBal = await duck.balanceOf(signer3.address);
      const carolBal = await duck.balanceOf(signer4.address);
      expect(totalSupply, '1100');
      expect(aliceBal, '90');
      expect(bobBal, '900');
      expect(carolBal, '110');
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
      ).to.be.revertedWith('DUCK: delegateByPowerBySig: invalid signature');
    });

    it('reverts if the nonce is bad', async () => {
      const delegatee = signer1.address;
      const nonce = BigNumber.from(1);
      const expiry = BigNumber.from(10e9);

      if (!network.config.chainId)
        throw new Error('Network must be configured with chain ID');

      const params = buildDelegateParams(
        network.config.chainId,
        duck.address,
        signer2.address,
        nonce.toString(),
        expiry.toString(),
      );

      const { r, s, v } = getSignatureFromTypedData(
        accounts[1].privateKey,
        params,
      );

      await expect(
        duck.delegateBySig(delegatee, nonce, expiry, v, r, s),
      ).to.be.revertedWith('DUCK: delegateByPowerBySig: invalid nonce');
    });

    it('reverts if the signature has expired', async () => {
      const delegatee = signer1.address;
      const nonce = BigNumber.from(0);
      const expiry = BigNumber.from(0);

      if (!network.config.chainId)
        throw new Error('Network must be configured with chain ID');

      const params = buildDelegateParams(
        network.config.chainId,
        duck.address,
        signer2.address,
        nonce.toString(),
        expiry.toString(),
      );

      const { r, s, v } = getSignatureFromTypedData(
        accounts[1].privateKey,
        params,
      );

      await expect(
        duck.delegateBySig(delegatee, nonce, expiry, v, r, s),
      ).to.be.revertedWith('DUCK: delegateByPowerBySig: invalid expiration');
    });

    //  it('delegates on behalf of the signatory', async () => {
    //    const delegatee = signer1.address;
    //    const nonce = (await duck._nonces(delegatee)).toString();
    //    const expiry = BigNumber.from(10e9);
    //
    //    if (!network.config.chainId)
    //      throw new Error('Network must be configured with chain ID');
    //
    //    const params = buildDelegateParams(
    //      network.config.chainId,
    //      duck.address,
    //        delegatee,
    //      nonce.toString(),
    //      expiry.toString(),
    //    );
    //
    //    const { r, s, v } = getSignatureFromTypedData(
    //      accounts[1].privateKey,
    //      params,
    //    );
    //
    //    expect(await duck.getDelegateeByPower(signer2.address, 1)).to.eq(signer2.address);
    //
    //    const tx = await duck.delegateBySig(delegatee, nonce, expiry, v, r, s);
    //
    //    await tx.wait();
    //
    //    /// @todo wallet address is different than when ECDSASignature
    // console.log(await duck.getDelegateeByPower(signer2.address, 1))
    //  });
  });
});

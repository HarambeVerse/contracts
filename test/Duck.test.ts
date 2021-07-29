import { ethers, network } from 'hardhat';
import { BigNumber, ContractTransaction } from 'ethers';
import chai from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { Duck, DuckMinter } from '../typechain';
import { accounts } from '../test-accounts';
import {
  deployDuck,
  deployDuckMinter,
} from '../helpers/contracts';
import { ContractId, DuckDS } from '../enums/Contract';

import {
  buildDelegateParams,
  buildPermitParams,
  getSignatureFromTypedData,
} from './utils';

const { expect } = chai;

const MAX_UINT_AMOUNT =
  '115792089237316195423570985008687907853269984665640564039457584007913129639935';

const waitForTx = async (tx: ContractTransaction) => tx.wait();

describe('Duck token', () => {
  const name = 'Duck Token';
  const symbol = 'DUCK';
  let signer1: SignerWithAddress;
  let signer2: SignerWithAddress;
  let signer3: SignerWithAddress;
  let signer4: SignerWithAddress;
  let duck: Duck;
  let minter: DuckMinter;

  before(async () => {
    [signer1, signer2, signer3, signer4] = await ethers.getSigners();

    duck = await deployDuck();
    minter = await deployDuckMinter(duck.address);
  });

  describe('metadata', () => {
    it('has given name', async () => {
      expect(await duck.name()).to.eq(name);
    });

    it('has given symbol', async () => {
      expect(await duck.symbol()).to.eq(symbol);
    });

    it('has generated DOMAIN', async () => {
      expect(await duck.DOMAIN_SEPARATOR()).to.equal(DuckDS.Hardhat);
    });
  });

  //
  describe('token', () => {
    it('should only allow owner to mint token', async () => {
      expect(await duck.setupMinter(minter.address))
        .to.emit(duck, 'MinterAdded')
        .withArgs(minter.address);

      await minter.mint(signer2.address, '100');
      await minter.mint(signer3.address, '1000');

      await expect(
        duck
          .connect(signer3)
          .mint(signer4.address, '1000', { from: signer3.address }),
      ).to.be.revertedWith('DuckAccessControl: Only minter');

      const totalSupply = await duck.totalSupply();
      const aliceBal = await duck.balanceOf(signer2.address);
      const bobBal = await duck.balanceOf(signer3.address);
      const carolBal = await duck.balanceOf(signer4.address);
      expect(totalSupply).to.equal('10000000000000001100');
      expect(aliceBal).to.equal('100');
      expect(bobBal).to.equal('1000');
      expect(carolBal).to.equal('0');
    });

    it('should supply token transfers properly', async () => {
      await minter.mint(signer2.address, '100');
      await minter.mint(signer3.address, '1000');
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

  describe('permit', () => {
    it('Reverts submitting a permit with 0 expiration', async () => {
      const owner = signer1.address;
      const spender = signer2.address;

      const { chainId } = network.config;
      if (!chainId) throw new Error('Network must be configured with chain ID');

      const expiration = 0;
      // eslint-disable-next-line no-underscore-dangle
      const nonce = (await duck._nonces(owner)).toNumber();
      const permitAmount = ethers.utils.parseEther('2').toString();

      const msgParams = buildPermitParams(
        chainId,
        duck.address,
        owner,
        spender,
        nonce,
        permitAmount,
        expiration.toFixed(),
      );

      const ownerPrivateKey = accounts[0].privateKey;

      if (!ownerPrivateKey) {
        throw new Error('INVALID_OWNER_PK');
      }

      expect((await duck.allowance(owner, spender)).toString()).to.be.equal(
        '0',
        'INVALID_ALLOWANCE_BEFORE_PERMIT',
      );

      const { r, s, v } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

      await expect(
        duck
          .connect(signer2)
          .permit(owner, spender, permitAmount, expiration, v, r, s),
      ).to.be.revertedWith('Duck:: invalid deadline');

      expect((await duck.allowance(owner, spender)).toString()).to.be.equal(
        '0',
        'INVALID_ALLOWANCE_AFTER_PERMIT',
      );
    });

    it('Submits a permit with maximum expiration length', async () => {
      const owner = signer1.address;
      const spender = signer2.address;

      const { chainId } = network.config;
      if (!chainId) throw new Error('Network must be configured with chain ID');

      const deadline = MAX_UINT_AMOUNT;
      // eslint-disable-next-line no-underscore-dangle
      const nonce = (await duck._nonces(owner)).toNumber();
      const permitAmount = ethers.utils.parseEther('2').toString();

      const msgParams = buildPermitParams(
        chainId,
        duck.address,
        owner,
        spender,
        nonce,
        deadline,
        permitAmount,
      );

      const ownerPrivateKey = accounts[0].privateKey;

      if (!ownerPrivateKey) {
        throw new Error('INVALID_OWNER_PK');
      }

      expect((await duck.allowance(owner, spender)).toString()).to.be.equal(
        '0',
        'INVALID_ALLOWANCE_BEFORE_PERMIT',
      );

      const { r, s, v } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

      await waitForTx(
        await duck
          .connect(signer2)
          .permit(owner, spender, permitAmount, deadline, v, r, s),
      );

      // eslint-disable-next-line no-underscore-dangle
      expect((await duck._nonces(owner)).toNumber()).to.be.equal(1);
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

    it('delegates on behalf of the signatory', async () => {
      if (!network.config.chainId)
        throw new Error('Network must be configured with chain ID');

      const nonce = (await duck._nonces(signer1.address)).toString();
      const expiration = MAX_UINT_AMOUNT;

      const msgParams = buildDelegateParams(
        network.config.chainId,
        duck.address,
        signer2.address,
        nonce,
        expiration,
      );

      const ownerPrivateKey = accounts[0].privateKey;

      if (!ownerPrivateKey) {
        throw new Error('INVALID_OWNER_PK');
      }

      const { r, s, v } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

      // Transmit tx via delegateByTypeBySig
      const tx = await duck.delegateBySig(
        signer2.address,
        nonce,
        expiration,
        v,
        r,
        s,
      );

      await expect(Promise.resolve(tx))
        .to.emit(duck, 'DelegateChanged')
        .withArgs(signer1.address, signer2.address, 0);

      await expect(Promise.resolve(tx))
        .to.emit(duck, 'DelegateChanged')
        .withArgs(signer1.address, signer2.address, 1);

      await expect(Promise.resolve(tx))
        .to.emit(duck, 'DelegatedPowerChanged')
        .withArgs(signer1.address, 0, 0);

      //
      await expect(Promise.resolve(tx))
        .to.emit(duck, 'DelegatedPowerChanged')
        .withArgs(signer2.address, BigNumber.from('10000000000000000190'), 0);

      await expect(Promise.resolve(tx))
        .to.emit(duck, 'DelegatedPowerChanged')
        .withArgs(signer1.address, 0, 1);

      //
      await expect(Promise.resolve(tx))
        .to.emit(duck, 'DelegatedPowerChanged')
        .withArgs(signer2.address, BigNumber.from('10000000000000000190'), 1);
    });
  });
});

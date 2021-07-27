import {
  defaultAbiCoder,
  keccak256,
  solidityPack,
  toUtf8Bytes,
} from 'ethers/lib/utils';
import { BigNumber, Contract } from 'ethers';

const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes(
    'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)',
  ),
);

const DELEGATE_TYPEHASH = keccak256(
  toUtf8Bytes('Delegation(address delegatee,uint256 nonce,uint256 expiry)'),
);

export const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';

function getDomainSeparatorNoVersion(name: string, tokenAddress: string) {
  return keccak256(
    defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'uint256', 'address'],
      [
        keccak256(
          toUtf8Bytes(
            'EIP712Domain(string name,uint256 chainId,address verifyingContract)',
          ),
        ),
        keccak256(toUtf8Bytes(name)),
        1,
        tokenAddress,
      ],
    ),
  );
}

export async function getDelegateDigest(
  token: Contract,
  delegate: {
    delegatee: string;
    expiry: BigNumber;
  },
  nonce: BigNumber,
): Promise<string> {
  const name = await token.name();
  const DOMAIN_SEPARATOR = getDomainSeparatorNoVersion(name, token.address);
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
        keccak256(
          defaultAbiCoder.encode(
            ['bytes32', 'address', 'uint256', 'uint256'],
            [DELEGATE_TYPEHASH, delegate.delegatee, nonce, delegate.expiry],
          ),
        ),
      ],
    ),
  );
}

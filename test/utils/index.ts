/* eslint-disable sort-keys-fix/sort-keys-fix */
import { ECDSASignature, fromRpcSig } from 'ethereumjs-util';
import { signTypedData_v4 } from 'eth-sig-util';

export const getSignatureFromTypedData = (
  privateKey: string,
  typedData: any,
): ECDSASignature => {
  const signature = signTypedData_v4(
    Buffer.from(privateKey.substring(2, 66), 'hex'),
    {
      data: typedData,
    },
  );

  return fromRpcSig(signature);
};

export const buildDelegateParams = (
  chainId: number,
  token: string,
  delegatee: string,
  nonce: string,
  expiry: string,
) => ({
  types: {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' },
    ],
    Delegate: [
      { name: 'delegatee', type: 'address' },
      { name: 'nonce', type: 'uint256' },
      { name: 'expiry', type: 'uint256' },
    ],
  },
  primaryType: 'Delegate' as const,
  domain: {
    name: 'Duck Token',
    version: '1',
    chainId,
    verifyingContract: token,
  },
  message: {
    delegatee,
    nonce,
    expiry,
  },
});

export const buildPermitParams = (
  chainId: number,
  token: string,
  owner: string,
  spender: string,
  nonce: number,
  deadline: string,
  value: string,
) => ({
  types: {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' },
    ],
    Permit: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  primaryType: 'Permit' as const,
  domain: {
    name: 'Duck Token',
    version: '1',
    chainId,
    verifyingContract: token,
  },
  message: {
    owner,
    spender,
    value,
    nonce,
    deadline,
  },
});

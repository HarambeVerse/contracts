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
  domain: {
    chainId,
    name: 'Duck',
    verifyingContract: token,
    version: '1',
  },
  message: {
    delegatee,
    expiry,
    nonce,
  },
  primaryType: 'Delegate',
  types: {
    Delegate: [
      { name: 'delegatee', type: 'address' },
      { name: 'nonce', type: 'uint256' },
      { name: 'expiry', type: 'uint256' },
    ],
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' },
    ],
  },
});

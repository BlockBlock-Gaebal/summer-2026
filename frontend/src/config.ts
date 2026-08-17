export const NETWORK = 'testnet' as const;

export const GRPC_URL =
  'https://fullnode.testnet.sui.io:443';

export const PACKAGE_ID =
  '0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60';

export const CHALLENGE_ID =
  new URLSearchParams(location.search).get('challenge')
  ?? '0xe11d89849787da8a028e515a17f2615ecf52da8d75415cbe983daa04f68bc4eb';

export const POLL_INTERVAL = 5000;
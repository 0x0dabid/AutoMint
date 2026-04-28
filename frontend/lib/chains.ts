import { defineChain } from "viem";

const RPC_HTTP = process.env.NEXT_PUBLIC_RPC_URL ?? "https://rpc.ritualfoundation.org";
const RPC_WS = process.env.NEXT_PUBLIC_RPC_WS_URL ?? "wss://rpc.ritualfoundation.org/ws";

export const ritualChain = defineChain({
  id: 1979,
  name: "Ritual Chain",
  nativeCurrency: { name: "RITUAL", symbol: "RITUAL", decimals: 18 },
  rpcUrls: {
    default: {
      http: [RPC_HTTP],
      webSocket: [RPC_WS],
    },
  },
  blockExplorers: {
    default: {
      name: "Ritual Explorer",
      url: "https://explorer.ritualfoundation.org",
    },
  },
  contracts: {
    multicall3: {
      address: "0x5577Ea679673Ec7508E9524100a188E7600202a3",
    },
  },
  testnet: true,
});

import { createConfig, http } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";
import { ritualChain } from "./chains";

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "automint-ritual";

export const wagmiConfig = createConfig({
  chains: [ritualChain],
  connectors: [
    injected(),
    walletConnect({ projectId }),
  ],
  transports: {
    // Prefer the server-side proxy so the browser never needs direct RPC access.
    // Falls back to the public RPC or whatever is set in NEXT_PUBLIC_RPC_URL.
    [ritualChain.id]: http(
      process.env.NEXT_PUBLIC_RPC_URL ?? "https://rpc.ritualfoundation.org",
    ),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}

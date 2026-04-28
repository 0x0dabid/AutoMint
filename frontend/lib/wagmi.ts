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
    [ritualChain.id]: http("https://rpc.ritualfoundation.org"),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}

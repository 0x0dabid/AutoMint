"use client";

import Link from "next/link";
import { useAccount, useConnect } from "wagmi";
import { injected } from "wagmi/connectors";
import { useReadContract } from "wagmi";
import { CONTRACT_ADDRESSES, FACTORY_ABI } from "@/lib/contracts";
import { AgentCard } from "@/components/AgentCard";
import { ritualChain } from "@/lib/chains";

export default function DashboardPage() {
  const { address, isConnected, chainId } = useAccount();
  const { connect } = useConnect();

  const { data: userAgents, isLoading } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: FACTORY_ABI,
    functionName: "getUserAgents",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const agents = (userAgents as `0x${string}`[]) ?? [];
  const wrongChain = isConnected && chainId !== ritualChain.id;

  return (
    <div className="space-y-8">
      {/* Hero */}
      <div className="border border-green-900/40 p-6 bg-green-950/10">
        <div className="text-green-400 font-mono text-xs uppercase tracking-widest mb-2">
          Ritual Chain ID: 1979
        </div>
        <h1 className="text-2xl font-bold text-white mb-2">AutoMint</h1>
        <p className="text-gray-400 text-sm max-w-xl">
          Deploy persistent NFT minting agents that mint autonomously — even while you&apos;re offline.
          Agents run as Persistent Agents on Ritual Chain, scheduled via the Scheduler system contract.
        </p>
      </div>

      {/* Wrong chain warning */}
      {wrongChain && (
        <div className="border border-red-800 bg-red-950/20 p-4 font-mono text-sm text-red-400">
          ⚠ Connected to wrong chain. Please switch to Ritual Chain (ID: 1979).
        </div>
      )}

      {/* Connect / Dashboard */}
      {!isConnected ? (
        <div className="border border-gray-800 p-8 text-center space-y-4">
          <div className="text-gray-500 text-sm">Connect your wallet to view and manage agents</div>
          <button
            onClick={() => connect({ connector: injected() })}
            className="font-mono text-sm text-green-400 border border-green-700 hover:border-green-400 px-6 py-2 transition-colors"
          >
            Connect Wallet
          </button>
        </div>
      ) : (
        <div className="space-y-6">
          {/* Stats bar */}
          <div className="grid grid-cols-3 gap-4">
            {[
              { label: "Your Agents", value: agents.length },
              { label: "Total Deployed", value: agents.length },
              { label: "Chain", value: "Ritual (1979)" },
            ].map(({ label, value }) => (
              <div key={label} className="border border-gray-800 p-3">
                <div className="text-gray-600 text-xs uppercase tracking-widest">{label}</div>
                <div className="text-green-400 text-lg font-bold">{value}</div>
              </div>
            ))}
          </div>

          {/* Agent list */}
          <div className="flex items-center justify-between">
            <h2 className="text-sm uppercase tracking-widest text-gray-400">Your Agents</h2>
            <Link
              href="/create"
              className="text-xs text-green-400 border border-green-800 hover:border-green-600 px-3 py-1 transition-colors"
            >
              + New Agent
            </Link>
          </div>

          {isLoading ? (
            <div className="text-gray-600 font-mono text-sm animate-pulse">Loading agents...</div>
          ) : agents.length === 0 ? (
            <div className="border border-gray-800 p-8 text-center space-y-3">
              <div className="text-gray-600 text-sm">No agents deployed yet.</div>
              <Link
                href="/create"
                className="inline-block text-xs text-green-400 border border-green-800 hover:border-green-500 px-4 py-2 transition-colors"
              >
                Deploy Your First Agent
              </Link>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {agents.map((agentAddr) => (
                <AgentCard key={agentAddr} agentAddress={agentAddr} />
              ))}
            </div>
          )}
        </div>
      )}

      {/* System info */}
      <div className="border border-gray-900 p-4">
        <div className="text-gray-600 text-xs uppercase tracking-widest mb-3">System Contracts</div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-2 font-mono text-xs">
          {[
            { label: "Scheduler", addr: CONTRACT_ADDRESSES.scheduler },
            { label: "RitualWallet", addr: CONTRACT_ADDRESSES.ritualWallet },
            { label: "AsyncDelivery", addr: CONTRACT_ADDRESSES.asyncDelivery },
            { label: "AsyncJobTracker", addr: CONTRACT_ADDRESSES.asyncJobTracker },
          ].map(({ label, addr }) => (
            <div key={label} className="flex gap-2 text-gray-600">
              <span className="text-gray-700 w-32">{label}</span>
              <a
                href={`https://explorer.ritualfoundation.org/address/${addr}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-gray-500 hover:text-green-400 truncate"
              >
                {addr}
              </a>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

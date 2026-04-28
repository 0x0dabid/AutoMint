"use client";

import Link from "next/link";
import { useReadContracts } from "wagmi";
import { AGENT_ABI } from "@/lib/contracts";
import { shortenAddress, agentStatus, agentStatusColor, explorerUrl, formatBlocks } from "@/lib/utils";
import { cn } from "@/lib/utils";

interface AgentCardProps {
  agentAddress: `0x${string}`;
}

export function AgentCard({ agentAddress }: AgentCardProps) {
  const { data } = useReadContracts({
    contracts: [
      { address: agentAddress, abi: AGENT_ABI, functionName: "isRunning" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "paused" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "executionCount" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "maxExecutions" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "nftContract" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "interval" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "lastHeartbeatBlock" },
    ],
  });

  const isRunning = (data?.[0]?.result as boolean) ?? false;
  const isPaused = (data?.[1]?.result as boolean) ?? false;
  const execCount = Number(data?.[2]?.result ?? 0);
  const maxExec = Number(data?.[3]?.result ?? 0);
  const nftContract = (data?.[4]?.result as `0x${string}`) ?? "0x0000000000000000000000000000000000000000";
  const interval = Number(data?.[5]?.result ?? 0);
  const lastHeartbeat = Number(data?.[6]?.result ?? 0);

  const status = agentStatus(isRunning, isPaused, execCount, maxExec);
  const progress = maxExec > 0 ? (execCount / maxExec) * 100 : 0;

  return (
    <div className="border border-green-900/40 bg-black/60 p-4 hover:border-green-700/60 transition-colors">
      {/* Header */}
      <div className="flex items-start justify-between mb-3">
        <div>
          <Link
            href={`/agents/${agentAddress}`}
            className="font-mono text-green-400 text-sm hover:underline"
          >
            {shortenAddress(agentAddress, 6)}
          </Link>
          <div className="text-gray-600 font-mono text-xs mt-0.5">
            NFT: {shortenAddress(nftContract)}
          </div>
        </div>
        <span className={cn("font-mono text-xs uppercase tracking-widest", agentStatusColor(status))}>
          ● {status}
        </span>
      </div>

      {/* Progress */}
      <div className="mb-3">
        <div className="flex justify-between font-mono text-xs text-gray-500 mb-1">
          <span>Mints</span>
          <span>{execCount} / {maxExec}</span>
        </div>
        <div className="h-1 bg-gray-800 rounded-none">
          <div
            className="h-1 bg-green-500 transition-all"
            style={{ width: `${Math.min(progress, 100)}%` }}
          />
        </div>
      </div>

      {/* Meta */}
      <div className="grid grid-cols-2 gap-2 font-mono text-xs text-gray-500">
        <div>
          <span className="text-gray-600">Interval</span>
          <br />
          <span className="text-gray-400">{formatBlocks(interval)}</span>
        </div>
        <div>
          <span className="text-gray-600">Last Heartbeat</span>
          <br />
          <span className="text-gray-400">{lastHeartbeat > 0 ? `Block ${lastHeartbeat}` : "—"}</span>
        </div>
      </div>

      {/* Links */}
      <div className="mt-3 flex gap-3 font-mono text-xs">
        <Link href={`/agents/${agentAddress}`} className="text-green-600 hover:text-green-400">
          Details →
        </Link>
        <a
          href={explorerUrl(`address/${agentAddress}`)}
          target="_blank"
          rel="noopener noreferrer"
          className="text-blue-600 hover:text-blue-400"
        >
          Explorer ↗
        </a>
      </div>
    </div>
  );
}

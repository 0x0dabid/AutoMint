"use client";

import { useParams } from "next/navigation";
import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { AGENT_ABI, HEARTBEAT_ABI, CONTRACT_ADDRESSES } from "@/lib/contracts";
import { TxStatusBadge } from "@/components/TxStatusBadge";
import { TxState } from "@/lib/tx-machine";
import { shortenAddress, agentStatus, agentStatusColor, explorerUrl } from "@/lib/utils";
import { cn } from "@/lib/utils";
import Link from "next/link";
import { useState } from "react";

export default function AgentDetailPage() {
  const params = useParams();
  const agentAddress = params.address as `0x${string}`;
  const { address: userAddress } = useAccount();

  const [txState, setTxState] = useState<TxState>("idle");

  const { data } = useReadContracts({
    contracts: [
      { address: agentAddress, abi: AGENT_ABI, functionName: "owner" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "isRunning" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "paused" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "executionCount" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "maxExecutions" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "nftContract" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "interval" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "lastHeartbeatBlock" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "condition" },
      { address: agentAddress, abi: AGENT_ABI, functionName: "getExecutionLog" },
      { address: CONTRACT_ADDRESSES.agentHeartbeat, abi: HEARTBEAT_ABI, functionName: "isActive", args: [agentAddress] },
      { address: CONTRACT_ADDRESSES.agentHeartbeat, abi: HEARTBEAT_ABI, functionName: "lastBeat", args: [agentAddress] },
    ],
  });

  const owner = data?.[0]?.result as `0x${string}` | undefined;
  const isRunning = (data?.[1]?.result as boolean) ?? false;
  const isPaused = (data?.[2]?.result as boolean) ?? false;
  const execCount = Number(data?.[3]?.result ?? 0);
  const maxExec = Number(data?.[4]?.result ?? 0);
  const nftContract = (data?.[5]?.result as `0x${string}`) ?? "0x0";
  const interval = Number(data?.[6]?.result ?? 0);
  const _lastHeartbeat = Number(data?.[7]?.result ?? 0); void _lastHeartbeat;
  const condition = (data?.[8]?.result as `0x${string}`) ?? "0x0";
  const executionLog = (data?.[9]?.result as { blockNumber: bigint; success: boolean; result: `0x${string}` }[]) ?? [];
  const heartbeatActive = (data?.[10]?.result as boolean) ?? false;
  const lastBeatBlock = Number(data?.[11]?.result ?? 0);

  const isOwner = userAddress && owner && userAddress.toLowerCase() === owner.toLowerCase();
  const status = agentStatus(isRunning, isPaused, execCount, maxExec);
  const progress = maxExec > 0 ? (execCount / maxExec) * 100 : 0;

  const { writeContract, data: txHash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  async function callAgent(functionName: string, args: unknown[] = []) {
    setTxState("awaiting_signature");
    try {
      writeContract({
        address: agentAddress,
        abi: AGENT_ABI,
        functionName: functionName as "start" | "cancel" | "pause" | "resume" | "withdraw" | "emergencyWithdraw",
        args: args as [],
      });
      setTxState("pending");
    } catch {
      setTxState("failed");
    }
  }

  const noCondition = condition === "0x0000000000000000000000000000000000000000" || condition === "0x0";

  return (
    <div className="space-y-6">
      {/* Breadcrumb */}
      <div className="flex items-center gap-2 font-mono text-xs text-gray-600">
        <Link href="/" className="hover:text-green-400">Dashboard</Link>
        <span>/</span>
        <span className="text-gray-400">Agent {shortenAddress(agentAddress)}</span>
      </div>

      {/* Header */}
      <div className="border border-green-900/40 p-5">
        <div className="flex items-start justify-between">
          <div>
            <div className="text-gray-600 text-xs uppercase tracking-widest mb-1">Agent</div>
            <div className="text-white font-mono text-sm">{agentAddress}</div>
          </div>
          <div className="text-right">
            <span className={cn("font-mono text-sm uppercase tracking-widest", agentStatusColor(status))}>
              ● {status}
            </span>
            {heartbeatActive && (
              <div className="text-green-600 text-xs mt-1">Heartbeat Active</div>
            )}
          </div>
        </div>

        {/* Progress */}
        <div className="mt-4">
          <div className="flex justify-between font-mono text-xs text-gray-500 mb-1">
            <span>Progress</span>
            <span>{execCount} / {maxExec} mints</span>
          </div>
          <div className="h-1.5 bg-gray-800">
            <div className="h-1.5 bg-green-500 transition-all" style={{ width: `${Math.min(progress, 100)}%` }} />
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Info panel */}
        <div className="md:col-span-2 space-y-4">
          {/* Details */}
          <div className="border border-gray-800 p-4">
            <div className="text-gray-600 text-xs uppercase tracking-widest mb-3">Configuration</div>
            <div className="grid grid-cols-2 gap-3 font-mono text-xs">
              {[
                { label: "Owner", value: owner ? shortenAddress(owner) : "—" },
                { label: "NFT Contract", value: shortenAddress(nftContract) },
                { label: "Interval", value: `${interval} blocks` },
                { label: "Max Executions", value: maxExec },
                { label: "Condition", value: noCondition ? "None" : shortenAddress(condition) },
                { label: "Last Heartbeat", value: lastBeatBlock > 0 ? `Block ${lastBeatBlock}` : "—" },
              ].map(({ label, value }) => (
                <div key={label}>
                  <div className="text-gray-600">{label}</div>
                  <div className="text-gray-300">{value}</div>
                </div>
              ))}
            </div>

            <div className="mt-3 flex gap-2 text-xs">
              <a
                href={explorerUrl(`address/${agentAddress}`)}
                target="_blank"
                rel="noopener noreferrer"
                className="text-blue-500 hover:text-blue-400"
              >
                View on Explorer ↗
              </a>
              <span className="text-gray-700">|</span>
              <a
                href={`https://explorer.ritualfoundation.org/agents`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-blue-500 hover:text-blue-400"
              >
                Agent Registry ↗
              </a>
            </div>
          </div>

          {/* Execution Log */}
          <div className="border border-gray-800 p-4">
            <div className="text-gray-600 text-xs uppercase tracking-widest mb-3">
              Execution Log ({executionLog.length})
            </div>
            {executionLog.length === 0 ? (
              <div className="text-gray-700 text-xs">No executions yet.</div>
            ) : (
              <div className="space-y-1 max-h-64 overflow-y-auto">
                {[...executionLog].reverse().map((entry, i) => (
                  <div
                    key={i}
                    className="flex items-center gap-3 font-mono text-xs border-b border-gray-900 pb-1"
                  >
                    <span className={entry.success ? "text-green-500" : "text-red-500"}>
                      {entry.success ? "✓" : "✗"}
                    </span>
                    <span className="text-gray-600">Block {Number(entry.blockNumber)}</span>
                    <span className={entry.success ? "text-green-600" : "text-red-600"}>
                      {entry.success ? "Minted" : "Failed"}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Controls */}
        <div className="space-y-3">
          <div className="border border-gray-800 p-4">
            <div className="text-gray-600 text-xs uppercase tracking-widest mb-3">Controls</div>

            {isOwner ? (
              <div className="space-y-2">
                {!isRunning && !isPaused && (
                  <ControlButton
                    label="Start Agent"
                    color="green"
                    onClick={() => callAgent("start", [10])}
                    disabled={txState === "pending"}
                  />
                )}
                {isRunning && !isPaused && (
                  <ControlButton
                    label="Pause"
                    color="amber"
                    onClick={() => callAgent("pause")}
                    disabled={txState === "pending"}
                  />
                )}
                {isPaused && (
                  <ControlButton
                    label="Resume"
                    color="green"
                    onClick={() => callAgent("resume")}
                    disabled={txState === "pending"}
                  />
                )}
                {isRunning && (
                  <ControlButton
                    label="Cancel"
                    color="red"
                    onClick={() => callAgent("cancel")}
                    disabled={txState === "pending"}
                  />
                )}
                <ControlButton
                  label="Withdraw Balance"
                  color="gray"
                  onClick={() => callAgent("withdraw")}
                  disabled={txState === "pending"}
                />
                <ControlButton
                  label="Emergency Withdraw"
                  color="red"
                  onClick={() => callAgent("emergencyWithdraw")}
                  disabled={txState === "pending"}
                />
              </div>
            ) : (
              <div className="text-gray-600 text-xs">You are not the owner of this agent.</div>
            )}

            <TxStatusBadge
              state={isConfirming ? "confirming" : isSuccess ? "confirmed" : txState}
              hash={txHash}
            />
          </div>

          {/* Transfer NFTs */}
          <div className="border border-gray-800 p-4">
            <div className="text-gray-600 text-xs uppercase tracking-widest mb-2">NFTs Held</div>
            <p className="text-gray-700 text-xs">
              NFTs minted to this agent can be transferred to your wallet from the{" "}
              <Link href="/gallery" className="text-green-600 hover:text-green-400">Gallery</Link>.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

function ControlButton({
  label,
  color,
  onClick,
  disabled,
}: {
  label: string;
  color: "green" | "amber" | "red" | "gray";
  onClick: () => void;
  disabled?: boolean;
}) {
  const colorMap = {
    green: "border-green-800 text-green-400 hover:border-green-600",
    amber: "border-amber-800 text-amber-400 hover:border-amber-600",
    red: "border-red-900 text-red-400 hover:border-red-700",
    gray: "border-gray-700 text-gray-400 hover:border-gray-500",
  };

  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "w-full py-2 font-mono text-xs uppercase tracking-widest border transition-colors",
        disabled ? "opacity-50 cursor-not-allowed" : colorMap[color]
      )}
    >
      {label}
    </button>
  );
}

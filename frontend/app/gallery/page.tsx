"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { CONTRACT_ADDRESSES, FACTORY_ABI, AGENT_ABI, ERC721_ABI } from "@/lib/contracts";
import { TxStatusBadge } from "@/components/TxStatusBadge";
import { TxState } from "@/lib/tx-machine";
import { shortenAddress } from "@/lib/utils";


function AgentNFTRow({
  agentAddress,
  userAddress,
}: {
  agentAddress: `0x${string}`;
  userAddress: `0x${string}`;
}) {
  const [txState, setTxState] = useState<TxState>("idle");
  const [selectedIds, setSelectedIds] = useState<bigint[]>([]);
  const [transferTo, setTransferTo] = useState("");

  const { data: nftContractAddr } = useReadContract({
    address: agentAddress,
    abi: AGENT_ABI,
    functionName: "nftContract",
  });

  const nftContract = nftContractAddr as `0x${string}` | undefined;

  const { data: balance } = useReadContract({
    address: nftContract,
    abi: ERC721_ABI,
    functionName: "balanceOf",
    args: nftContract ? [agentAddress] : undefined,
    query: { enabled: !!nftContract },
  });

  const { data: nftName } = useReadContract({
    address: nftContract,
    abi: ERC721_ABI,
    functionName: "name",
    query: { enabled: !!nftContract },
  });

  const { writeContract, data: txHash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const balanceNum = Number(balance ?? 0);

  async function handleTransfer() {
    if (!nftContract || selectedIds.length === 0) return;
    const to = (transferTo || userAddress) as `0x${string}`;
    setTxState("awaiting_signature");
    try {
      if (selectedIds.length === 1) {
        writeContract({
          address: agentAddress,
          abi: AGENT_ABI,
          functionName: "transferNFT",
          args: [nftContract, selectedIds[0], to],
        });
      } else {
        writeContract({
          address: agentAddress,
          abi: AGENT_ABI,
          functionName: "batchTransferNFT",
          args: [nftContract, selectedIds, to],
        });
      }
      setTxState("pending");
    } catch {
      setTxState("failed");
    }
  }

  if (balanceNum === 0) return null;

  return (
    <div className="border border-gray-800 p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-gray-400 font-mono text-sm">{nftName ?? "Unknown NFT"}</div>
          <div className="text-gray-600 font-mono text-xs">
            Agent: {shortenAddress(agentAddress)} — {balanceNum} NFT{balanceNum !== 1 ? "s" : ""}
          </div>
        </div>
        <div className="text-green-400 font-mono text-sm">{balanceNum} held</div>
      </div>

      {/* Token IDs placeholder (would need enumerable ERC-721 or indexed events) */}
      <div className="text-gray-700 font-mono text-xs">
        This agent holds {balanceNum} token{balanceNum !== 1 ? "s" : ""} from {shortenAddress(nftContract ?? "0x0")}.
        Use token IDs from the explorer to transfer below.
      </div>

      {/* Transfer form */}
      <div className="space-y-2">
        <input
          type="text"
          placeholder="Token IDs (comma-separated, e.g. 1,2,3)"
          onChange={(e) => {
            const ids = e.target.value
              .split(",")
              .map((s) => s.trim())
              .filter(Boolean)
              .map((s) => BigInt(s));
            setSelectedIds(ids);
          }}
          className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-xs focus:outline-none focus:border-green-700"
        />
        <input
          type="text"
          placeholder={`Transfer to (default: ${shortenAddress(userAddress)})`}
          value={transferTo}
          onChange={(e) => setTransferTo(e.target.value)}
          className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-xs focus:outline-none focus:border-green-700"
        />
        <button
          onClick={handleTransfer}
          disabled={selectedIds.length === 0 || txState === "pending"}
          className="px-4 py-2 font-mono text-xs border border-green-800 text-green-400 hover:border-green-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Transfer {selectedIds.length > 0 ? `(${selectedIds.length})` : ""}
        </button>
        <TxStatusBadge
          state={isConfirming ? "confirming" : isSuccess ? "confirmed" : txState}
          hash={txHash}
        />
      </div>
    </div>
  );
}

export default function GalleryPage() {
  const { address, isConnected } = useAccount();

  const { data: userAgents } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: FACTORY_ABI,
    functionName: "getUserAgents",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const agents = (userAgents as `0x${string}`[]) ?? [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-bold text-white">NFT Gallery</h1>
        <p className="text-gray-500 text-sm mt-1">
          View and transfer NFTs held by your mint agents
        </p>
      </div>

      {!isConnected ? (
        <div className="border border-gray-800 p-8 text-center text-gray-600 text-sm">
          Connect your wallet to view your NFT gallery.
        </div>
      ) : agents.length === 0 ? (
        <div className="border border-gray-800 p-8 text-center text-gray-600 text-sm">
          No agents deployed. Deploy an agent first to start minting.
        </div>
      ) : (
        <div className="space-y-4">
          <div className="text-gray-600 font-mono text-xs uppercase tracking-widest">
            Scanning {agents.length} agent{agents.length !== 1 ? "s" : ""} for NFTs
          </div>
          {agents.map((agentAddr) => (
            <AgentNFTRow
              key={agentAddr}
              agentAddress={agentAddr}
              userAddress={address!}
            />
          ))}
        </div>
      )}
    </div>
  );
}

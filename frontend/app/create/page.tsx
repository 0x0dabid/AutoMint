"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract } from "wagmi";
import { encodeAbiParameters, parseAbiParameters, formatEther } from "viem";
import { CONTRACT_ADDRESSES, FACTORY_ABI, ERC721_ABI } from "@/lib/contracts";
import { TxStatusBadge } from "@/components/TxStatusBadge";
import { TxState } from "@/lib/tx-machine";
import { cn } from "@/lib/utils";

const CONDITION_PRESETS = [
  { label: "None", value: "none", address: "0x0000000000000000000000000000000000000000" },
  { label: "Supply Gate (custom)", value: "supply", address: "" },
  { label: "Price Gate (custom)", value: "price", address: "" },
  { label: "Time Gate (2am-4am UTC)", value: "time", address: "" },
  { label: "Custom address", value: "custom", address: "" },
];

const MINT_SELECTORS = [
  { label: "mint(address,uint256)", value: "0x40c10f19" },
  { label: "mint(address)", value: "0x6a627842" },
  { label: "mintTo(address)", value: "0x449a52f8" },
  { label: "publicMint(uint256)", value: "0x2db11544" },
  { label: "Custom", value: "custom" },
];

export default function CreateAgentPage() {
  const { address, isConnected } = useAccount();

  const [form, setForm] = useState({
    nftContract: "",
    mintSelectorPreset: "0x40c10f19",
    mintSelectorCustom: "",
    mintTo: "",
    mintQty: "1",
    interval: "200",
    maxExecutions: "10",
    conditionPreset: "none",
    conditionAddress: "",
    initialDelay: "10",
  });

  const [txState, setTxState] = useState<TxState>("idle");

  // Read mintPrice from the NFT contract when a valid address is entered
  const isValidAddress = /^0x[0-9a-fA-F]{40}$/.test(form.nftContract);
  const { data: mintPriceRaw } = useReadContract({
    address: form.nftContract as `0x${string}`,
    abi: ERC721_ABI,
    functionName: "mintPrice",
    query: { enabled: isValidAddress },
  });

  const { writeContract, data: createHash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: createHash });

  function getMintSelector(): `0x${string}` {
    if (form.mintSelectorPreset === "custom") return form.mintSelectorCustom as `0x${string}`;
    return form.mintSelectorPreset as `0x${string}`;
  }

  function getMintArgs(): `0x${string}` {
    const to = (form.mintTo || address || "0x0000000000000000000000000000000000000000") as `0x${string}`;
    const qty = BigInt(form.mintQty || "1");
    // Encode address + uint256
    return encodeAbiParameters(
      parseAbiParameters("address, uint256"),
      [to, qty]
    ) as `0x${string}`;
  }

  function getConditionAddress(): `0x${string}` {
    if (form.conditionPreset === "none") return "0x0000000000000000000000000000000000000000";
    if (form.conditionPreset === "custom") return (form.conditionAddress || "0x0000000000000000000000000000000000000000") as `0x${string}`;
    return (form.conditionAddress || "0x0000000000000000000000000000000000000000") as `0x${string}`;
  }

  async function handleCreate() {
    if (!isConnected || !address) return;

    setTxState("awaiting_signature");

    try {
      writeContract({
        address: CONTRACT_ADDRESSES.factory,
        abi: FACTORY_ABI,
        functionName: "createAgent",
        args: [
          form.nftContract as `0x${string}`,
          getMintSelector(),
          getMintArgs(),
          Number(form.interval),
          Number(form.maxExecutions),
          getConditionAddress(),
        ],
      });
      setTxState("pending");
    } catch (e: unknown) {
      setTxState("failed");
      console.error(e);
    }
  }

  // Cost estimate: mint price × quantity × executions (from contract, not hardcoded)
  const mintPrice = typeof mintPriceRaw === "bigint" ? mintPriceRaw : 0n;
  const qty = BigInt(form.mintQty || "1");
  const totalMintCost = mintPrice * qty * BigInt(form.maxExecutions || "0");
  const estimatedCost = totalMintCost > 0n ? formatEther(totalMintCost) : "—";

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <h1 className="text-xl font-bold text-white">Deploy Mint Agent</h1>
        <p className="text-gray-500 text-sm mt-1">
          Configure your autonomous minting agent on Ritual Chain
        </p>
      </div>

      {!isConnected && (
        <div className="border border-amber-800 bg-amber-950/20 p-3 text-amber-400 text-sm">
          Connect your wallet to deploy an agent.
        </div>
      )}

      <div className="space-y-4">
        {/* NFT Contract */}
        <Field label="NFT Contract Address" required>
          <input
            type="text"
            placeholder="0x..."
            value={form.nftContract}
            onChange={(e) => setForm({ ...form, nftContract: e.target.value })}
            className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
          />
        </Field>

        {/* Mint Function */}
        <Field label="Mint Function">
          <select
            value={form.mintSelectorPreset}
            onChange={(e) => setForm({ ...form, mintSelectorPreset: e.target.value })}
            className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
          >
            {MINT_SELECTORS.map(({ label, value }) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
          {form.mintSelectorPreset === "custom" && (
            <input
              type="text"
              placeholder="0x40c10f19"
              value={form.mintSelectorCustom}
              onChange={(e) => setForm({ ...form, mintSelectorCustom: e.target.value })}
              className="mt-2 w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
            />
          )}
        </Field>

        {/* Mint recipient + quantity */}
        <div className="grid grid-cols-2 gap-4">
          <Field label="Mint To">
            <input
              type="text"
              placeholder={address ?? "0x... (defaults to you)"}
              value={form.mintTo}
              onChange={(e) => setForm({ ...form, mintTo: e.target.value })}
              className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
            />
          </Field>
          <Field label="Quantity per Mint">
            <input
              type="number"
              min="1"
              value={form.mintQty}
              onChange={(e) => setForm({ ...form, mintQty: e.target.value })}
              className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
            />
          </Field>
        </div>

        {/* Schedule */}
        <div className="grid grid-cols-2 gap-4">
          <Field label="Interval (blocks)">
            <input
              type="number"
              min="1"
              value={form.interval}
              onChange={(e) => setForm({ ...form, interval: e.target.value })}
              className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
            />
            <p className="text-gray-600 text-xs mt-1">
              ≈ {Math.round(Number(form.interval) * 12 / 60)} min between mints
            </p>
          </Field>
          <Field label="Max Executions">
            <input
              type="number"
              min="1"
              value={form.maxExecutions}
              onChange={(e) => setForm({ ...form, maxExecutions: e.target.value })}
              className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
            />
          </Field>
        </div>

        {/* Initial delay */}
        <Field label="Initial Delay (blocks)">
          <input
            type="number"
            min="0"
            value={form.initialDelay}
            onChange={(e) => setForm({ ...form, initialDelay: e.target.value })}
            className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
          />
          <p className="text-gray-600 text-xs mt-1">Blocks to wait before first mint</p>
        </Field>

        {/* Condition */}
        <Field label="Mint Condition (optional)">
          <select
            value={form.conditionPreset}
            onChange={(e) => setForm({ ...form, conditionPreset: e.target.value })}
            className="w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
          >
            {CONDITION_PRESETS.map(({ label, value }) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
          {form.conditionPreset !== "none" && (
            <input
              type="text"
              placeholder="Condition contract address (0x...)"
              value={form.conditionAddress}
              onChange={(e) => setForm({ ...form, conditionAddress: e.target.value })}
              className="mt-2 w-full bg-black border border-gray-800 text-gray-300 px-3 py-2 font-mono text-sm focus:outline-none focus:border-green-700"
            />
          )}
        </Field>

        {/* Cost estimate */}
        <div className="border border-gray-800 p-3 bg-black/40">
          <div className="text-gray-600 text-xs uppercase tracking-widest mb-2">Estimated Cost</div>
          <div className="grid grid-cols-2 gap-1 text-xs font-mono">
            <span className="text-gray-600">Executions:</span>
            <span className="text-gray-300">{form.maxExecutions}</span>
            <span className="text-gray-600">Mint price (contract):</span>
            <span className="text-gray-300">
              {isValidAddress && mintPrice > 0n ? `${formatEther(mintPrice)} RITUAL` : isValidAddress ? "free" : "enter contract"}
            </span>
            <span className="text-gray-600">Total mint cost:</span>
            <span className="text-green-400">{estimatedCost !== "—" ? `${estimatedCost} RITUAL` : "—"}</span>
          </div>
        </div>

        {/* Deploy button */}
        <button
          onClick={handleCreate}
          disabled={!isConnected || txState === "pending" || txState === "confirming"}
          className={cn(
            "w-full py-3 font-mono text-sm uppercase tracking-widest transition-colors",
            isConnected && txState === "idle"
              ? "bg-green-900/40 border border-green-700 text-green-400 hover:bg-green-900/60 hover:border-green-500"
              : "bg-gray-900 border border-gray-700 text-gray-600 cursor-not-allowed"
          )}
        >
          {txState === "pending" || txState === "confirming" ? "Deploying..." : "Deploy Agent"}
        </button>

        <TxStatusBadge
          state={isConfirming ? "confirming" : isSuccess ? "confirmed" : txState}
          hash={createHash}
        />

        {isSuccess && (
          <div className="border border-green-700 bg-green-950/20 p-4 text-green-400 text-sm">
            ✓ Agent deployed! Check your dashboard for the new agent.
          </div>
        )}
      </div>
    </div>
  );
}

function Field({ label, children, required }: { label: string; children: React.ReactNode; required?: boolean }) {
  return (
    <div className="space-y-1.5">
      <label className="font-mono text-xs text-gray-500 uppercase tracking-widest">
        {label} {required && <span className="text-red-500">*</span>}
      </label>
      {children}
    </div>
  );
}

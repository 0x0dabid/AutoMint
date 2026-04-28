"use client";

import { TxState, TX_STATE_LABELS, TX_STATE_COLORS } from "@/lib/tx-machine";
import { cn } from "@/lib/utils";
import { explorerUrl } from "@/lib/utils";

interface TxStatusBadgeProps {
  state: TxState;
  hash?: `0x${string}`;
  error?: string;
}

export function TxStatusBadge({ state, hash, error }: TxStatusBadgeProps) {
  if (state === "idle") return null;

  return (
    <div className="mt-3 p-3 border border-gray-800 bg-black/50 font-mono text-xs space-y-1">
      <div className="flex items-center gap-2">
        {state !== "confirmed" && state !== "failed" && (
          <span className="inline-block w-2 h-2 bg-amber-400 rounded-full animate-pulse" />
        )}
        <span className={cn(TX_STATE_COLORS[state])}>{TX_STATE_LABELS[state]}</span>
      </div>

      {hash && (
        <a
          href={explorerUrl(`tx/${hash}`)}
          target="_blank"
          rel="noopener noreferrer"
          className="text-blue-400 hover:underline block truncate"
        >
          {hash.slice(0, 20)}...
        </a>
      )}

      {error && <span className="text-red-400">{error}</span>}
    </div>
  );
}

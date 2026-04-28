// 9-state async TX machine for tracking transaction lifecycle

export type TxState =
  | "idle"
  | "preparing"
  | "awaiting_signature"
  | "signing"
  | "broadcasting"
  | "pending"
  | "confirming"
  | "confirmed"
  | "failed";

export interface TxStatus {
  state: TxState;
  hash?: `0x${string}`;
  error?: string;
  confirmations?: number;
}

export const TX_STATE_LABELS: Record<TxState, string> = {
  idle: "Ready",
  preparing: "Preparing...",
  awaiting_signature: "Awaiting Signature",
  signing: "Signing...",
  broadcasting: "Broadcasting...",
  pending: "Pending",
  confirming: "Confirming...",
  confirmed: "Confirmed",
  failed: "Failed",
};

export const TX_STATE_COLORS: Record<TxState, string> = {
  idle: "text-gray-400",
  preparing: "text-amber-400",
  awaiting_signature: "text-amber-400",
  signing: "text-amber-400",
  broadcasting: "text-blue-400",
  pending: "text-blue-400",
  confirming: "text-blue-400",
  confirmed: "text-green-400",
  failed: "text-red-400",
};

export function isTerminal(state: TxState): boolean {
  return state === "confirmed" || state === "failed";
}

export function isActive(state: TxState): boolean {
  return !isTerminal(state) && state !== "idle";
}

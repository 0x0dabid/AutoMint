import { clsx, type ClassValue } from "clsx";

export function cn(...inputs: ClassValue[]) {
  return clsx(inputs);
}

export function shortenAddress(address: string, chars = 4): string {
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
}

export function formatBlocks(blocks: number): string {
  if (blocks < 100) return `~${blocks} blocks`;
  if (blocks < 7200) return `~${Math.round(blocks / 12 / 60)}m`;
  return `~${Math.round(blocks / 12 / 3600)}h`;
}

export function explorerUrl(path: string): string {
  return `https://explorer.ritualfoundation.org/${path}`;
}

export function agentStatus(isRunning: boolean, paused: boolean, executionCount: number, maxExecutions: number): string {
  if (executionCount >= maxExecutions) return "Completed";
  if (!isRunning && !paused) return "Stopped";
  if (paused) return "Paused";
  if (isRunning) return "Active";
  return "Idle";
}

export function agentStatusColor(status: string): string {
  switch (status) {
    case "Active": return "text-green-400";
    case "Paused": return "text-amber-400";
    case "Completed": return "text-blue-400";
    case "Stopped": return "text-gray-400";
    default: return "text-gray-400";
  }
}

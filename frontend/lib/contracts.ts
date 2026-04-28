// Contract addresses — update after deployment
export const CONTRACT_ADDRESSES = {
  factory: (process.env.NEXT_PUBLIC_FACTORY_ADDRESS ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,
  sampleNFT: (process.env.NEXT_PUBLIC_SAMPLE_NFT_ADDRESS ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,
  // System contracts (fixed on Ritual Chain — do not change)
  scheduler: "0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B" as `0x${string}`,
  ritualWallet: "0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948" as `0x${string}`,
  asyncDelivery: "0x5A16214fF555848411544b005f7Ac063742f39F6" as `0x${string}`,
  asyncJobTracker: "0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5" as `0x${string}`,
  teeServiceRegistry: "0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F" as `0x${string}`,
  sovereignAgentFactory: "0x9dC4C054e53bCc4Ce0A0Ff09E890A7a8e817f304" as `0x${string}`,
};

// ── AutoMintFactory ABI ───────────────────────────────────────────────────────
export const FACTORY_ABI = [
  {
    type: "function",
    name: "createAgent",
    inputs: [
      { name: "nftContract", type: "address" },
      { name: "mintSelector", type: "bytes4" },
      { name: "mintArgs", type: "bytes" },
      { name: "interval", type: "uint32" },
      { name: "maxExecutions", type: "uint32" },
      { name: "condition", type: "address" },
    ],
    outputs: [{ name: "agent", type: "address" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getUserAgents",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "agentOwner",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalAgents",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "AgentCreated",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "agent", type: "address", indexed: true },
      { name: "nftContract", type: "address", indexed: false },
      { name: "maxExecutions", type: "uint32", indexed: false },
    ],
  },
] as const;

// ── AutoMintAgent ABI ─────────────────────────────────────────────────────────
export const AGENT_ABI = [
  {
    type: "function",
    name: "start",
    inputs: [{ name: "initialDelay", type: "uint32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "cancel",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "pause",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "resume",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "withdraw",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "emergencyWithdraw",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "transferNFT",
    inputs: [
      { name: "nftAddr", type: "address" },
      { name: "tokenId", type: "uint256" },
      { name: "to", type: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "batchTransferNFT",
    inputs: [
      { name: "nftAddr", type: "address" },
      { name: "tokenIds", type: "uint256[]" },
      { name: "to", type: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "updateParams",
    inputs: [
      { name: "_nftContract", type: "address" },
      { name: "_mintSelector", type: "bytes4" },
      { name: "_mintArgs", type: "bytes" },
      { name: "_interval", type: "uint32" },
      { name: "_maxExecutions", type: "uint32" },
      { name: "_condition", type: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getStatus",
    inputs: [],
    outputs: [
      { name: "_isRunning", type: "bool" },
      { name: "_paused", type: "bool" },
      { name: "_executionCount", type: "uint32" },
      { name: "_maxExecutions", type: "uint32" },
      { name: "_conditionMet", type: "bool" },
      { name: "_executor", type: "address" },
      { name: "_harness", type: "address" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getExecutionLog",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "tuple[]",
        components: [
          { name: "blockNumber", type: "uint256" },
          { name: "success", type: "bool" },
          { name: "result", type: "bytes" },
        ],
      },
    ],
    stateMutability: "view",
  },
  { type: "function", name: "owner", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "nftContract", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "interval", inputs: [], outputs: [{ name: "", type: "uint32" }], stateMutability: "view" },
  { type: "function", name: "maxExecutions", inputs: [], outputs: [{ name: "", type: "uint32" }], stateMutability: "view" },
  { type: "function", name: "executionCount", inputs: [], outputs: [{ name: "", type: "uint32" }], stateMutability: "view" },
  { type: "function", name: "isRunning", inputs: [], outputs: [{ name: "", type: "bool" }], stateMutability: "view" },
  { type: "function", name: "paused", inputs: [], outputs: [{ name: "", type: "bool" }], stateMutability: "view" },
  { type: "function", name: "condition", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "executor", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "harness", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  {
    type: "function",
    name: "launchHarness",
    inputs: [
      { name: "salt", type: "bytes32" },
      { name: "frequency", type: "uint32" },
      { name: "windowNumCalls", type: "uint32" },
      { name: "lockDuration", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
  { type: "function", name: "stopHarness", inputs: [], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "restartHarness", inputs: [], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "initExecutor", inputs: [], outputs: [], stateMutability: "nonpayable" },
  {
    type: "function",
    name: "setExecutor",
    inputs: [{ name: "_executor", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "HarnessDeployed",
    inputs: [{ name: "harness", type: "address", indexed: true }],
  },
  { type: "receive", stateMutability: "payable" },
] as const;

// ── AgentHeartbeat ABI ────────────────────────────────────────────────────────
export const HEARTBEAT_ABI = [
  {
    type: "function",
    name: "isActive",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "lastBeat",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "blockNumber", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

// ── ERC-721 minimal ABI ───────────────────────────────────────────────────────
export const ERC721_ABI = [
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "ownerOf",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "tokenURI",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalSupply",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "name",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "mintPrice",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

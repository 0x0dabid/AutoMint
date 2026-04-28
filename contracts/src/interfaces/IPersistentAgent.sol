// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Precompile 0x0820 — Persistent Agent
interface IPersistentAgent {
    struct AgentConfig {
        string manifestCid;
        uint32 heartbeatInterval;
        bool autoRevive;
    }

    function register(AgentConfig calldata config) external returns (bytes32 agentId);

    function deregister(bytes32 agentId) external;

    function postCheckpoint(bytes32 agentId, string calldata checkpointCid) external;

    function revive(bytes32 agentId) external;
}

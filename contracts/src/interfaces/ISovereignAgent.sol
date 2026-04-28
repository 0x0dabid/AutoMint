// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Precompile 0x080C — Sovereign Agent (TEE execution)
interface ISovereignAgent {
    struct JobParams {
        string modelId;
        bytes input;
        uint256 maxTokens;
        address callbackContract;
        bytes4 callbackSelector;
    }

    function submitJob(JobParams calldata params) external returns (bytes32 jobId);

    function getJobStatus(bytes32 jobId) external view returns (uint8 status);
}

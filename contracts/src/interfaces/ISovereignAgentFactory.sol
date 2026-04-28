// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// 0x9dC4C054e53bCc4Ce0A0Ff09E890A7a8e817f304
// Deploys SovereignAgentHarness contracts that appear on the Ritual explorer.

struct StorageRef {
    string platform;
    string path;
    string keyRef;
}

struct SovereignAgentParams {
    address  executor;
    uint256  ttl;
    bytes    userPublicKey;
    uint64   pollIntervalBlocks;
    uint64   maxPollBlock;
    string   taskIdMarker;
    address  deliveryTarget;
    bytes4   deliverySelector;
    uint256  deliveryGasLimit;
    uint256  deliveryMaxFeePerGas;
    uint256  deliveryMaxPriorityFeePerGas;
    uint16   cliType;
    string   prompt;
    bytes    encryptedSecrets;
    StorageRef convoHistory;
    StorageRef output;
    StorageRef[] skills;
    StorageRef systemPrompt;
    string   model;
    string[] tools;
    uint16   maxTurns;
    uint32   maxTokens;
    string   rpcUrls;
}

struct SovereignScheduleConfig {
    uint32  schedulerGas;
    uint32  frequency;
    uint32  schedulerTtl;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    uint256 value;
}

struct SovereignRollingConfig {
    uint32 windowNumCalls;
    uint16 rolloverThresholdBps;
    uint16 rolloverRetryEveryCalls;
}

interface ISovereignAgentFactory {
    function deployHarness(bytes32 userSalt) external returns (address harness);

    function predictHarness(address owner, bytes32 userSalt)
        external
        view
        returns (address predicted, bytes32 salt);
}

interface ISovereignAgentHarness {
    function configureFundAndStart(
        SovereignAgentParams calldata agentParams,
        SovereignScheduleConfig calldata scheduleConfig,
        SovereignRollingConfig calldata rollingConfig,
        uint256 lockDuration
    ) external payable returns (uint256 jobId);

    function stop() external;

    function restart() external returns (uint256 jobId);
}

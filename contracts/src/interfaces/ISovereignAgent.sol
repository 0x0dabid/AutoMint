// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Precompile 0x080C — Sovereign Agent (TEE execution)
//
// The precompile has NO named function selector. It is invoked via a raw
// low-level call:
//
//   (bool ok, bytes memory out) = address(0x080C).call(encoded);
//
// where `encoded` is abi.encode() of the 23 fields below IN ORDER.
// Phase 1 returns a bytes32 jobId; Phase 2 delivers results via the
// callback specified in fields 6-8.

library SovereignAgentLib {
    // StorageRef is used for convoHistory, output, systemPrompt, and the
    // skills array. An empty ref is ("", "", "").
    struct StorageRef {
        string platform; // "gcs", "hf", "pinata", or ""
        string path;     // object key / file path
        string keyRef;   // env-var name holding the credential
    }

    // Build the 23-field ABI payload for the 0x080C precompile.
    //
    // Field order (must match exactly):
    //  0  executor               address
    //  1  ttl                   uint256
    //  2  userPublicKey         bytes
    //  3  pollIntervalBlocks    uint64
    //  4  maxPollBlock          uint64
    //  5  taskIdMarker          string
    //  6  deliveryTarget        address
    //  7  deliverySelector      bytes4
    //  8  deliveryGasLimit      uint256
    //  9  deliveryMaxFeePerGas  uint256
    // 10  deliveryMaxPriorityFee uint256
    // 11  cliType               uint16  (6 = ZeroClaw, no API key w/ Ritual)
    // 12  prompt                string
    // 13  encryptedSecrets      bytes
    // 14  convoHistory          StorageRef
    // 15  output                StorageRef
    // 16  skills                StorageRef[]
    // 17  systemPrompt          StorageRef
    // 18  model                 string
    // 19  tools                 string[]
    // 20  maxTurns              uint16
    // 21  maxTokens             uint32
    // 22  rpcUrls               string
    function encode(
        address executor,
        uint256 ttl,
        address deliveryTarget,
        bytes4 deliverySelector,
        uint256 deliveryGasLimit,
        string memory prompt,
        bytes memory encryptedSecrets,
        string memory model,
        string memory rpcUrls
    ) internal pure returns (bytes memory) {
        StorageRef memory empty = StorageRef("", "", "");
        StorageRef[] memory noSkills = new StorageRef[](0);
        string[] memory noTools = new string[](0);

        return abi.encode(
            executor,           // 0
            ttl,                // 1
            bytes(""),          // 2  userPublicKey (empty = plaintext output)
            uint64(10),         // 3  pollIntervalBlocks
            uint64(500),        // 4  maxPollBlock
            "",                 // 5  taskIdMarker
            deliveryTarget,     // 6
            deliverySelector,   // 7
            deliveryGasLimit,   // 8
            uint256(20 gwei),   // 9  deliveryMaxFeePerGas
            uint256(1 gwei),    // 10 deliveryMaxPriorityFeePerGas
            uint16(6),          // 11 cliType: ZeroClaw (Ritual provider, no key)
            prompt,             // 12
            encryptedSecrets,   // 13
            empty,              // 14 convoHistory
            empty,              // 15 output
            noSkills,           // 16 skills
            empty,              // 17 systemPrompt
            model,              // 18
            noTools,            // 19 tools (empty = all)
            uint16(3),          // 20 maxTurns
            uint32(500),        // 21 maxTokens
            rpcUrls             // 22
        );
    }
}

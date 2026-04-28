// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAgentHeartbeat {
    function register(string calldata manifestCid) external;

    function beat(string calldata manifestCid) external;

    function deregister() external;

    function isActive(address agent) external view returns (bool);

    function lastBeat(address agent) external view returns (uint256 blockNumber);

    function manifestCid(address agent) external view returns (string memory);
}

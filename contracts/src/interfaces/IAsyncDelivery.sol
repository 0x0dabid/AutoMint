// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAsyncDelivery {
    function deliver(bytes32 jobId, bytes calldata result) external;

    function pendingResult(bytes32 jobId) external view returns (bool exists, bytes memory result);
}

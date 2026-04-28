// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IScheduler {
    struct ScheduleParams {
        address target;
        bytes4 selector;
        bytes args;
        uint32 interval;
        uint32 maxExecutions;
        address condition;
    }

    function schedule(ScheduleParams calldata params) external payable returns (bytes32 jobId);

    function cancel(bytes32 jobId) external;

    function getJob(bytes32 jobId)
        external
        view
        returns (
            address target,
            bytes4 selector,
            bytes memory args,
            uint32 interval,
            uint32 maxExecutions,
            uint32 executionCount,
            address condition,
            bool active
        );
}

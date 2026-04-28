// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F
// Executor discovery — never hardcode executor addresses; always look them up.
interface ITEEServiceRegistry {
    function pickServiceByCapability(
        uint256 capability,
        bool active,
        uint256 seed,
        uint256 maxProbes
    ) external view returns (address executor, bool found);

    function getServicesByCapability(uint256 capability, bool active)
        external
        view
        returns (address[] memory);
}

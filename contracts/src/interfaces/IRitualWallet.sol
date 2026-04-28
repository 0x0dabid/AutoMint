// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRitualWallet {
    function deposit(address account) external payable;

    function withdraw(address account, uint256 amount) external;

    function lock(address account, uint256 amount) external;

    function unlock(address account, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function lockedBalanceOf(address account) external view returns (uint256);

    function emergencyWithdraw(address account) external;
}

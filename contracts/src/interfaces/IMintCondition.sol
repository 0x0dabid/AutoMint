// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMintCondition {
    function shouldMint(address nftContract, address minter) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {AutoMintAgent} from "./AutoMintAgent.sol";

contract AutoMintFactory is Ownable, Pausable {
    using Clones for address;

    address public immutable agentImplementation;

    // user → list of agents
    mapping(address => address[]) private _userAgents;

    // agent → user (reverse lookup)
    mapping(address => address) public agentOwner;

    // global agent list
    address[] public allAgents;

    // default parameters
    uint32 public defaultInterval = 100;
    uint32 public defaultMaxExecutions = 10;

    event AgentCreated(address indexed user, address indexed agent, address nftContract, uint32 maxExecutions);
    event DefaultsUpdated(uint32 interval, uint32 maxExecutions);

    error AgentNotOwnedByUser();

    constructor() Ownable(msg.sender) {
        agentImplementation = address(new AutoMintAgent());
    }

    // ── Create ────────────────────────────────────────────────────────────────

    function createAgent(
        address nftContract,
        bytes4 mintSelector,
        bytes calldata mintArgs,
        uint32 interval,
        uint32 maxExecutions,
        address condition
    ) external whenNotPaused returns (address agent) {
        uint32 _interval = interval == 0 ? defaultInterval : interval;
        uint32 _maxExecutions = maxExecutions == 0 ? defaultMaxExecutions : maxExecutions;

        agent = agentImplementation.clone();

        AutoMintAgent(payable(agent)).initialize(
            msg.sender, nftContract, mintSelector, mintArgs, _interval, _maxExecutions, condition
        );

        _userAgents[msg.sender].push(agent);
        agentOwner[agent] = msg.sender;
        allAgents.push(agent);

        emit AgentCreated(msg.sender, agent, nftContract, _maxExecutions);
    }

    // ── View ──────────────────────────────────────────────────────────────────

    function getUserAgents(address user) external view returns (address[] memory) {
        return _userAgents[user];
    }

    function getAllAgents() external view returns (address[] memory) {
        return allAgents;
    }

    function totalAgents() external view returns (uint256) {
        return allAgents.length;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function setDefaults(uint32 _interval, uint32 _maxExecutions) external onlyOwner {
        defaultInterval = _interval;
        defaultMaxExecutions = _maxExecutions;
        emit DefaultsUpdated(_interval, _maxExecutions);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IScheduler} from "./interfaces/IScheduler.sol";
import {IRitualWallet} from "./interfaces/IRitualWallet.sol";
import {IAgentHeartbeat} from "./interfaces/IAgentHeartbeat.sol";
import {ISovereignAgent} from "./interfaces/ISovereignAgent.sol";
import {IPersistentAgent} from "./interfaces/IPersistentAgent.sol";
import {IMintCondition} from "./interfaces/IMintCondition.sol";

contract AutoMintAgent is IERC721Receiver, ReentrancyGuard {
    // ── System contracts ──────────────────────────────────────────────────────
    address public constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address public constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address public constant AGENT_HEARTBEAT = 0xEF505E801f1Db392B5289690E2ffc20e840A3aCa;
    address public constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;

    // ── Precompiles ───────────────────────────────────────────────────────────
    address public constant PERSISTENT_AGENT_PRECOMPILE = 0x0000000000000000000000000000000000000820;
    address public constant SOVEREIGN_AGENT_PRECOMPILE = 0x000000000000000000000000000000000000080C;

    // ── Heartbeat & wallet ────────────────────────────────────────────────────
    uint256 public constant HEARTBEAT_INTERVAL = 100; // blocks
    uint256 public constant LOCK_DURATION = 5000;     // blocks to lock RitualWallet deposit
    string public constant MANIFEST_CID = "bafybeiabc123automint"; // updated post-deploy

    // ── State ─────────────────────────────────────────────────────────────────
    address public owner;
    address public factory;
    bool public initialized;
    bool public isRunning;
    bool public paused;

    address public nftContract;
    bytes4 public mintSelector;
    bytes public mintArgs;
    uint32 public interval;
    uint32 public maxExecutions;
    uint32 public executionCount;
    address public condition;

    bytes32 public currentJobId;       // Scheduler job id for wakeUp
    bytes32 public sovereignJobId;     // Sovereign Agent TEE job id
    bytes32 public persistentAgentId;  // Persistent Agent registration id

    uint256 public lastHeartbeatBlock;

    mapping(bytes32 => bool) private _processed; // idempotency guard for async callbacks

    struct ExecutionRecord {
        uint256 blockNumber;
        bool success;
        bytes result;
    }
    ExecutionRecord[] public executionLog;

    // ── Events ────────────────────────────────────────────────────────────────
    event AgentStarted(address indexed owner, address indexed nftContract, uint32 maxExecutions);
    event WakeUpCalled(uint256 indexed executionIndex, uint256 blockNumber);
    event MintAttempted(uint256 indexed executionIndex, bool success);
    event ConditionFailed(uint256 indexed executionIndex, address condition);
    event HeartbeatPosted(uint256 blockNumber);
    event AgentCancelled(address indexed owner);
    event AgentPaused(address indexed owner);
    event AgentResumed(address indexed owner);
    event NFTTransferred(address indexed to, uint256 tokenId);
    event BalanceWithdrawn(address indexed to, uint256 amount);

    // ── Errors ────────────────────────────────────────────────────────────────
    error NotOwner();
    error NotFactory();
    error NotScheduler();
    error NotAsyncDelivery();
    error AlreadyInitialized();
    error AlreadyRunning();
    error NotRunning();
    error Paused();
    error MaxExecutionsReached();
    error NotPausedOrStopped();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    modifier onlyScheduler() {
        if (msg.sender != SCHEDULER) revert NotScheduler();
        _;
    }

    modifier onlyAsyncDelivery() {
        if (msg.sender != ASYNC_DELIVERY) revert NotAsyncDelivery();
        _;
    }

    modifier notPaused() {
        if (paused) revert Paused();
        _;
    }

    // ── Initializer ───────────────────────────────────────────────────────────

    function initialize(
        address _owner,
        address _nftContract,
        bytes4 _mintSelector,
        bytes calldata _mintArgs,
        uint32 _interval,
        uint32 _maxExecutions,
        address _condition
    ) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        factory = msg.sender;
        owner = _owner;
        nftContract = _nftContract;
        mintSelector = _mintSelector;
        mintArgs = _mintArgs;
        interval = _interval;
        maxExecutions = _maxExecutions;
        condition = _condition;
    }

    // ── Start / Cancel ────────────────────────────────────────────────────────

    function start(uint32 initialDelay) external onlyOwner notPaused {
        if (isRunning) revert AlreadyRunning();
        isRunning = true;

        // Register on Persistent Agent precompile (best-effort — may not exist in test env)
        _tryRegisterPersistentAgent();

        // Register on AgentHeartbeat contract
        _tryRegisterHeartbeat();

        // Schedule first wakeUp
        _scheduleNext(initialDelay);

        emit AgentStarted(owner, nftContract, maxExecutions);
    }

    function cancel() external onlyOwner {
        isRunning = false;

        if (currentJobId != bytes32(0)) {
            try IScheduler(SCHEDULER).cancel(currentJobId) {} catch {}
            currentJobId = bytes32(0);
        }

        _tryDeregisterHeartbeat();

        emit AgentCancelled(owner);
    }

    // ── Wake-up (called by Scheduler at scheduled block) ─────────────────────

    function wakeUp(uint256 executionIndex) external onlyScheduler nonReentrant {
        emit WakeUpCalled(executionIndex, block.number);

        if (!isRunning || paused) return;
        if (executionCount >= maxExecutions) {
            isRunning = false;
            return;
        }

        // Check optional mint condition
        if (condition != address(0)) {
            bool conditionMet = false;
            try IMintCondition(condition).shouldMint(nftContract, address(this)) returns (bool ok) {
                conditionMet = ok;
            } catch {}
            if (!conditionMet) {
                emit ConditionFailed(executionCount, condition);
                _scheduleNext(interval);
                return;
            }
        }

        // Invoke Sovereign Agent precompile for TEE-executed mint
        _invokeSovereignMint();

        // Post heartbeat if enough blocks have passed
        if (block.number >= lastHeartbeatBlock + HEARTBEAT_INTERVAL) {
            _postHeartbeat();
        }

        // Schedule next wakeUp
        if (executionCount + 1 < maxExecutions) {
            _scheduleNext(interval);
        } else {
            isRunning = false;
        }
    }

    // ── Sovereign Agent result callback (Phase 2) ─────────────────────────────

    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        if (jobId != sovereignJobId) return;
        if (_processed[jobId]) return;
        _processed[jobId] = true;

        bool success = result.length > 0 && result[0] == 0x01;

        executionLog.push(ExecutionRecord({blockNumber: block.number, success: success, result: result}));

        executionCount++;

        emit MintAttempted(executionCount, success);
        sovereignJobId = bytes32(0);
    }

    // ── Pause / Resume ────────────────────────────────────────────────────────

    function pause() external onlyOwner {
        paused = true;
        emit AgentPaused(owner);
    }

    function resume() external onlyOwner {
        paused = false;
        if (isRunning && currentJobId == bytes32(0)) {
            _scheduleNext(interval);
        }
        emit AgentResumed(owner);
    }

    // ── Update params (only when paused or not running) ───────────────────────

    function updateParams(
        address _nftContract,
        bytes4 _mintSelector,
        bytes calldata _mintArgs,
        uint32 _interval,
        uint32 _maxExecutions,
        address _condition
    ) external onlyOwner {
        if (!paused && isRunning) revert NotPausedOrStopped();
        nftContract = _nftContract;
        mintSelector = _mintSelector;
        mintArgs = _mintArgs;
        interval = _interval;
        maxExecutions = _maxExecutions;
        condition = _condition;
    }

    // ── Fund / Withdraw ───────────────────────────────────────────────────────

    function depositToRitualWallet() external payable onlyOwner {
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}(LOCK_DURATION);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool ok,) = owner.call{value: balance}("");
            require(ok, "withdraw failed");
            emit BalanceWithdrawn(owner, balance);
        }
    }

    function emergencyWithdraw() external onlyOwner nonReentrant {
        isRunning = false;
        paused = true;

        try IRitualWallet(RITUAL_WALLET).emergencyWithdraw(address(this)) {} catch {}

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool ok,) = owner.call{value: balance}("");
            require(ok, "emergency withdraw failed");
            emit BalanceWithdrawn(owner, balance);
        }
    }

    // ── NFT management ────────────────────────────────────────────────────────

    function transferNFT(address nftAddr, uint256 tokenId, address to) external onlyOwner {
        IERC721(nftAddr).transferFrom(address(this), to, tokenId);
        emit NFTTransferred(to, tokenId);
    }

    function batchTransferNFT(address nftAddr, uint256[] calldata tokenIds, address to) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(nftAddr).transferFrom(address(this), to, tokenIds[i]);
            emit NFTTransferred(to, tokenIds[i]);
        }
    }

    // ── View helpers ──────────────────────────────────────────────────────────

    function getExecutionLog() external view returns (ExecutionRecord[] memory) {
        return executionLog;
    }

    function getStatus()
        external
        view
        returns (bool _isRunning, bool _paused, uint32 _executionCount, uint32 _maxExecutions, bool _conditionMet)
    {
        _isRunning = isRunning;
        _paused = paused;
        _executionCount = executionCount;
        _maxExecutions = maxExecutions;

        if (condition != address(0)) {
            try IMintCondition(condition).shouldMint(nftContract, address(this)) returns (bool ok) {
                _conditionMet = ok;
            } catch {
                _conditionMet = false;
            }
        } else {
            _conditionMet = true;
        }
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    function _scheduleNext(uint32 delay) internal {
        bytes memory callData = abi.encodeWithSelector(AutoMintAgent.wakeUp.selector, uint256(executionCount));

        IScheduler.ScheduleParams memory params = IScheduler.ScheduleParams({
            target: address(this),
            selector: AutoMintAgent.wakeUp.selector,
            args: abi.encode(uint256(executionCount)),
            interval: delay,
            maxExecutions: 1,
            condition: address(0)
        });

        try IScheduler(SCHEDULER).schedule(params) returns (bytes32 jobId) {
            currentJobId = jobId;
        } catch {}
    }

    function _invokeSovereignMint() internal {
        // Build mint calldata from stored selector + args
        bytes memory mintCalldata = abi.encodePacked(mintSelector, mintArgs);

        ISovereignAgent.JobParams memory params = ISovereignAgent.JobParams({
            modelId: "automint-v1",
            input: mintCalldata,
            maxTokens: 0,
            callbackContract: address(this),
            callbackSelector: AutoMintAgent.onSovereignAgentResult.selector
        });

        try ISovereignAgent(SOVEREIGN_AGENT_PRECOMPILE).submitJob(params) returns (bytes32 jobId) {
            sovereignJobId = jobId;
        } catch {
            // Fallback: execute mint directly if TEE not available (test environments)
            _executeMintDirect();
        }
    }

    function _executeMintDirect() internal {
        bytes memory callData = abi.encodePacked(mintSelector, mintArgs);
        (bool success, bytes memory result) = nftContract.call{value: _getMintValue()}(callData);

        executionLog.push(ExecutionRecord({blockNumber: block.number, success: success, result: result}));

        executionCount++;
        emit MintAttempted(executionCount, success);
    }

    function _getMintValue() internal view returns (uint256) {
        // Try reading mint price from the NFT contract
        (bool ok, bytes memory data) = nftContract.staticcall(abi.encodeWithSignature("mintPrice()"));
        if (ok && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    function _postHeartbeat() internal {
        lastHeartbeatBlock = block.number;
        try IAgentHeartbeat(AGENT_HEARTBEAT).beat(MANIFEST_CID) {
            emit HeartbeatPosted(block.number);
        } catch {}
    }

    function _tryRegisterHeartbeat() internal {
        try IAgentHeartbeat(AGENT_HEARTBEAT).register(MANIFEST_CID) {
            lastHeartbeatBlock = block.number;
        } catch {}
    }

    function _tryDeregisterHeartbeat() internal {
        try IAgentHeartbeat(AGENT_HEARTBEAT).deregister() {} catch {}
    }

    function _tryRegisterPersistentAgent() internal {
        IPersistentAgent.AgentConfig memory config = IPersistentAgent.AgentConfig({
            manifestCid: MANIFEST_CID,
            heartbeatInterval: uint32(HEARTBEAT_INTERVAL),
            autoRevive: true
        });
        try IPersistentAgent(PERSISTENT_AGENT_PRECOMPILE).register(config) returns (bytes32 agentId) {
            persistentAgentId = agentId;
        } catch {}
    }

    // ── ERC-721 Receiver ──────────────────────────────────────────────────────

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IScheduler} from "./interfaces/IScheduler.sol";
import {IRitualWallet} from "./interfaces/IRitualWallet.sol";
import {ISovereignAgent, SovereignAgentLib} from "./interfaces/ISovereignAgent.sol";
import {ITEEServiceRegistry} from "./interfaces/ITEEServiceRegistry.sol";
import {IMintCondition} from "./interfaces/IMintCondition.sol";

contract AutoMintAgent is IERC721Receiver, ReentrancyGuard {
    using Strings for address;
    using Strings for uint256;

    // ── System contracts ──────────────────────────────────────────────────────
    address public constant SCHEDULER      = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address public constant RITUAL_WALLET  = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address public constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address public constant TEE_REGISTRY   = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;

    // ── Precompile ────────────────────────────────────────────────────────────
    address public constant SOVEREIGN_AGENT_PRECOMPILE = 0x000000000000000000000000000000000000080C;

    // ── Sovereign Agent config ────────────────────────────────────────────────
    uint256 public constant LOCK_DURATION  = 5000;   // blocks for RitualWallet deposit
    uint256 public constant SOVEREIGN_TTL  = 200;    // blocks until job expires
    uint256 public constant DELIVERY_GAS   = 300_000;
    // ZeroClaw runtime with Ritual provider — no LLM API key required
    string  public constant SOVEREIGN_MODEL = "ritual/meta-llama-3.1-8b-instruct";
    string  public constant RPC_URLS = '{"ritual":"https://rpc.ritualfoundation.org"}';

    // ── State ─────────────────────────────────────────────────────────────────
    address public owner;
    address public factory;
    bool public initialized;
    bool public isRunning;
    bool public paused;

    address public nftContract;
    bytes4  public mintSelector;
    bytes   public mintArgs;
    uint32  public interval;
    uint32  public maxExecutions;
    uint32  public executionCount;
    address public condition;

    // Executor selected from TEEServiceRegistry — must be set before start()
    address public executor;

    // Pre-encoded ECIES secrets blob; set by owner off-chain.
    // For the Ritual LLM provider this can be empty bytes since no API key is needed.
    bytes public encryptedSecrets;

    bytes32 public currentJobId;    // active Scheduler job
    bytes32 public sovereignJobId;  // active Sovereign Agent TEE job

    mapping(bytes32 => bool) private _processed; // idempotency for async callbacks

    struct ExecutionRecord {
        uint256 blockNumber;
        bool    success;
        bytes   result;
    }
    ExecutionRecord[] public executionLog;

    // ── Events ────────────────────────────────────────────────────────────────
    event AgentStarted(address indexed owner, address indexed nftContract, uint32 maxExecutions);
    event WakeUpCalled(uint256 indexed executionIndex, uint256 blockNumber);
    event MintAttempted(uint256 indexed executionIndex, bool success);
    event ConditionFailed(uint256 indexed executionIndex, address condition);
    event SovereignJobSubmitted(bytes32 indexed jobId);
    event SovereignJobFailed(string reason);
    event ExecutorInitialized(address indexed executor);
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
    error ExecutorNotSet();
    error NoExecutorFound();
    error WithdrawFailed();

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
        bytes4  _mintSelector,
        bytes calldata _mintArgs,
        uint32  _interval,
        uint32  _maxExecutions,
        address _condition
    ) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        factory        = msg.sender;
        owner          = _owner;
        nftContract    = _nftContract;
        mintSelector   = _mintSelector;
        mintArgs       = _mintArgs;
        interval       = _interval;
        maxExecutions  = _maxExecutions;
        condition      = _condition;
    }

    // ── Executor selection ────────────────────────────────────────────────────

    /// Select a live TEE executor from the registry.
    /// Must be called before start(). Uses the current block hash as a random
    /// seed so each agent clone picks independently.
    function initExecutor() external onlyOwner {
        (address picked, bool found) = ITEEServiceRegistry(TEE_REGISTRY).pickServiceByCapability(
            0, // capability 0 = generic compute / Sovereign Agent
            true,
            uint256(blockhash(block.number - 1)),
            5  // max probes
        );
        if (!found) revert NoExecutorFound();
        executor = picked;
        emit ExecutorInitialized(picked);
    }

    /// Owner can manually override the executor (e.g. after registry update).
    function setExecutor(address _executor) external onlyOwner {
        if (_executor == address(0)) revert ExecutorNotSet();
        executor = _executor;
        emit ExecutorInitialized(_executor);
    }

    /// Set the pre-encrypted secrets blob (ECIES-encrypted off-chain).
    /// For the Ritual LLM provider this may be left empty.
    function setEncryptedSecrets(bytes calldata _secrets) external onlyOwner {
        encryptedSecrets = _secrets;
    }

    // ── Start / Cancel ────────────────────────────────────────────────────────

    function start(uint32 initialDelay) external onlyOwner notPaused {
        if (isRunning) revert AlreadyRunning();
        if (executor == address(0)) revert ExecutorNotSet();
        isRunning = true;
        _scheduleNext(initialDelay);
        emit AgentStarted(owner, nftContract, maxExecutions);
    }

    function cancel() external onlyOwner {
        isRunning = false;
        if (currentJobId != bytes32(0)) {
            try IScheduler(SCHEDULER).cancel(currentJobId) {} catch {}
            currentJobId = bytes32(0);
        }
        emit AgentCancelled(owner);
    }

    // ── Wake-up (called by Scheduler) ─────────────────────────────────────────

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

        // Submit a Sovereign Agent TEE job for the mint
        _invokeSovereignMint();

        // Schedule next wakeUp (executionCount increments in the Phase 2 callback)
        if (executionCount + 1 < maxExecutions) {
            _scheduleNext(interval);
        } else {
            isRunning = false;
        }
    }

    // ── Sovereign Agent Phase 2 callback ──────────────────────────────────────

    /// Called by AsyncDelivery (0x5A16...) when the TEE job completes.
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        if (jobId != sovereignJobId) return;
        if (_processed[jobId]) return;
        _processed[jobId] = true;

        // Unwrap Phase 2 envelope: (bytes simmedInput, bytes actualOutput)
        // Then read the first bool (success) from the agent response tuple.
        bool success = false;
        if (result.length > 0) {
            try this._decodeSuccess(result) returns (bool s) {
                success = s;
            } catch {}
        }

        executionLog.push(ExecutionRecord({blockNumber: block.number, success: success, result: result}));
        executionCount++;
        emit MintAttempted(executionCount, success);
        sovereignJobId = bytes32(0);
    }

    /// External helper so we can use try/catch on abi.decode.
    function _decodeSuccess(bytes calldata raw) external pure returns (bool success) {
        // Unwrap the (simmedInput, actualOutput) envelope
        (, bytes memory inner) = abi.decode(raw, (bytes, bytes));
        // First field of the agent response tuple is the bool success flag
        if (inner.length >= 32) {
            success = abi.decode(inner[0:32], (bool));
        }
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

    // ── Update params (only when paused or stopped) ───────────────────────────

    function updateParams(
        address _nftContract,
        bytes4  _mintSelector,
        bytes calldata _mintArgs,
        uint32  _interval,
        uint32  _maxExecutions,
        address _condition
    ) external onlyOwner {
        if (!paused && isRunning) revert NotPausedOrStopped();
        nftContract   = _nftContract;
        mintSelector  = _mintSelector;
        mintArgs      = _mintArgs;
        interval      = _interval;
        maxExecutions = _maxExecutions;
        condition     = _condition;
    }

    // ── Fund / Withdraw ───────────────────────────────────────────────────────

    function depositToRitualWallet() external payable onlyOwner {
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}(LOCK_DURATION);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool ok,) = owner.call{value: balance}("");
            if (!ok) revert WithdrawFailed();
            emit BalanceWithdrawn(owner, balance);
        }
    }

    function emergencyWithdraw() external onlyOwner nonReentrant {
        isRunning = false;
        paused    = true;
        try IRitualWallet(RITUAL_WALLET).emergencyWithdraw(address(this)) {} catch {}
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool ok,) = owner.call{value: balance}("");
            if (!ok) revert WithdrawFailed();
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
        returns (
            bool _isRunning,
            bool _paused,
            uint32 _executionCount,
            uint32 _maxExecutions,
            bool _conditionMet,
            address _executor
        )
    {
        _isRunning      = isRunning;
        _paused         = paused;
        _executionCount = executionCount;
        _maxExecutions  = maxExecutions;
        _executor       = executor;

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
        IScheduler.ScheduleParams memory params = IScheduler.ScheduleParams({
            target:        address(this),
            selector:      AutoMintAgent.wakeUp.selector,
            args:          abi.encode(uint256(executionCount)),
            interval:      delay,
            maxExecutions: 1,
            condition:     address(0)
        });
        try IScheduler(SCHEDULER).schedule(params) returns (bytes32 jobId) {
            currentJobId = jobId;
        } catch {}
    }

    function _invokeSovereignMint() internal {
        // Build mint calldata
        bytes memory mintCalldata = abi.encodePacked(mintSelector, mintArgs);

        // Build a plain-English prompt the ZeroClaw agent can act on
        string memory prompt = string.concat(
            "Execute an NFT mint on Ritual Chain (chainId 1979). ",
            "Send a transaction to contract ", nftContract.toHexString(),
            " with the following hex calldata: 0x", _toHex(mintCalldata),
            ". Use eth_sendRawTransaction. Do not ask for confirmation."
        );

        // Encode the 23-field Sovereign Agent input
        bytes memory encoded = SovereignAgentLib.encode(
            executor,
            SOVEREIGN_TTL,
            address(this),
            AutoMintAgent.onSovereignAgentResult.selector,
            DELIVERY_GAS,
            prompt,
            encryptedSecrets,
            SOVEREIGN_MODEL,
            RPC_URLS
        );

        // Raw call — the precompile has no function selector
        (bool ok, bytes memory out) = SOVEREIGN_AGENT_PRECOMPILE.call(encoded);

        if (!ok) {
            emit SovereignJobFailed("precompile call reverted");
            _executeMintDirect(); // fallback for test environments
            return;
        }

        if (out.length < 32) {
            emit SovereignJobFailed("precompile returned no jobId");
            _executeMintDirect();
            return;
        }

        bytes32 jobId = abi.decode(out, (bytes32));
        if (jobId == bytes32(0)) {
            emit SovereignJobFailed("precompile returned zero jobId");
            _executeMintDirect();
            return;
        }

        sovereignJobId = jobId;
        emit SovereignJobSubmitted(jobId);
    }

    function _executeMintDirect() internal {
        bytes memory callData = abi.encodePacked(mintSelector, mintArgs);
        (bool success, bytes memory result) = nftContract.call{value: _getMintValue()}(callData);
        executionLog.push(ExecutionRecord({blockNumber: block.number, success: success, result: result}));
        executionCount++;
        emit MintAttempted(executionCount, success);
    }

    function _getMintValue() internal view returns (uint256) {
        (bool ok, bytes memory data) = nftContract.staticcall(abi.encodeWithSignature("mintPrice()"));
        if (ok && data.length >= 32) return abi.decode(data, (uint256));
        return 0;
    }

    // Convert bytes to their lowercase hex string representation
    function _toHex(bytes memory data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(2 * data.length);
        for (uint256 i = 0; i < data.length; i++) {
            result[2 * i]     = hexChars[uint8(data[i]) >> 4];
            result[2 * i + 1] = hexChars[uint8(data[i]) & 0x0f];
        }
        return string(result);
    }

    // ── ERC-721 Receiver ──────────────────────────────────────────────────────

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}

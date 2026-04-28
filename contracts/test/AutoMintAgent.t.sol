// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AutoMintAgent} from "../src/AutoMintAgent.sol";
import {AutoMintFactory} from "../src/AutoMintFactory.sol";
import {SampleNFT} from "../src/SampleNFT.sol";
import {SupplyGateCondition} from "../src/MintConditions.sol";

contract AutoMintAgentTest is Test {
    AutoMintFactory internal factory;
    AutoMintAgent   internal agent;
    SampleNFT       internal nft;

    address internal owner        = makeAddr("owner");
    address internal scheduler    = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address internal asyncDelivery = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address internal ritualWallet = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address internal teeRegistry  = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address internal mockExecutor = makeAddr("executor");

    bytes4 constant MINT_SELECTOR = SampleNFT.mint.selector;

    function setUp() public {
        factory = new AutoMintFactory();
        nft = new SampleNFT("TestNFT", "TNFT", 1000, 0, 100);

        // Mock system contracts so calls don't revert
        vm.mockCall(scheduler, abi.encodeWithSignature("schedule((address,bytes4,bytes,uint32,uint32,address))"), abi.encode(bytes32(uint256(1))));
        vm.mockCall(scheduler, abi.encodeWithSignature("cancel(bytes32)"), abi.encode());
        vm.mockCall(ritualWallet, abi.encodeWithSignature("deposit(uint256)"), abi.encode());
        vm.mockCall(ritualWallet, abi.encodeWithSignature("emergencyWithdraw(address)"), abi.encode());

        // Mock TEEServiceRegistry to return mockExecutor
        vm.mockCall(
            teeRegistry,
            abi.encodeWithSignature("pickServiceByCapability(uint256,bool,uint256,uint256)"),
            abi.encode(mockExecutor, true)
        );

        // Create agent via factory
        bytes memory mintArgs = abi.encode(owner, uint256(1));
        vm.prank(owner);
        address agentAddr = factory.createAgent(address(nft), MINT_SELECTOR, mintArgs, 50, 5, address(0));
        agent = AutoMintAgent(payable(agentAddr));
    }

    // ── Initialization ────────────────────────────────────────────────────────

    function test_cannotReinitialize() public {
        vm.expectRevert(AutoMintAgent.AlreadyInitialized.selector);
        agent.initialize(owner, address(nft), MINT_SELECTOR, bytes(""), 50, 5, address(0));
    }

    function test_ownerIsSet() public view {
        assertEq(agent.owner(), owner);
    }

    // ── Executor selection ────────────────────────────────────────────────────

    function test_initExecutorStoresAddress() public {
        vm.prank(owner);
        agent.initExecutor();
        assertEq(agent.executor(), mockExecutor);
    }

    function test_initExecutorEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit AutoMintAgent.ExecutorInitialized(mockExecutor);
        agent.initExecutor();
    }

    function test_initExecutorRevertsWhenNoneFound() public {
        vm.mockCall(
            teeRegistry,
            abi.encodeWithSignature("pickServiceByCapability(uint256,bool,uint256,uint256)"),
            abi.encode(address(0), false)
        );
        vm.prank(owner);
        vm.expectRevert(AutoMintAgent.NoExecutorFound.selector);
        agent.initExecutor();
    }

    function test_setExecutorManual() public {
        address custom = makeAddr("custom");
        vm.prank(owner);
        agent.setExecutor(custom);
        assertEq(agent.executor(), custom);
    }

    function test_setExecutorZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(AutoMintAgent.ExecutorNotSet.selector);
        agent.setExecutor(address(0));
    }

    // ── Start / Cancel ────────────────────────────────────────────────────────

    function _startAgent() internal {
        vm.startPrank(owner);
        agent.initExecutor();
        agent.start(0);
        vm.stopPrank();
    }

    function test_onlyOwnerCanStart() public {
        vm.prank(owner);
        agent.initExecutor();
        vm.prank(makeAddr("hacker"));
        vm.expectRevert(AutoMintAgent.NotOwner.selector);
        agent.start(0);
    }

    function test_startRevertsWithoutExecutor() public {
        vm.prank(owner);
        vm.expectRevert(AutoMintAgent.ExecutorNotSet.selector);
        agent.start(0);
    }

    function test_startSetsRunning() public {
        _startAgent();
        assertTrue(agent.isRunning());
    }

    function test_cannotStartTwice() public {
        _startAgent();
        vm.prank(owner);
        vm.expectRevert(AutoMintAgent.AlreadyRunning.selector);
        agent.start(0);
    }

    function test_cancelStopsAgent() public {
        _startAgent();
        vm.prank(owner);
        agent.cancel();
        assertFalse(agent.isRunning());
    }

    // ── Pause / Resume ────────────────────────────────────────────────────────

    function test_pauseAndResume() public {
        _startAgent();
        vm.startPrank(owner);
        agent.pause();
        assertTrue(agent.paused());
        agent.resume();
        assertFalse(agent.paused());
        vm.stopPrank();
    }

    function test_pausedAgentCannotStart() public {
        vm.startPrank(owner);
        agent.initExecutor();
        agent.pause();
        vm.expectRevert(AutoMintAgent.Paused.selector);
        agent.start(0);
        vm.stopPrank();
    }

    // ── WakeUp ────────────────────────────────────────────────────────────────

    function test_onlySchedulerCanCallWakeUp() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(AutoMintAgent.NotScheduler.selector);
        agent.wakeUp(0);
    }

    function test_wakeUpDoesNothingWhenPaused() public {
        _startAgent();
        vm.prank(owner);
        agent.pause();

        vm.prank(scheduler);
        agent.wakeUp(0);
        assertEq(agent.executionCount(), 0);
    }

    function test_wakeUpDoesNothingWhenNotRunning() public {
        vm.prank(scheduler);
        agent.wakeUp(0);
        assertEq(agent.executionCount(), 0);
    }

    /// When the sovereign precompile is unavailable the agent falls back to
    /// a direct mint and increments executionCount in the same call.
    function test_wakeUpFallsBackToDirectMint() public {
        _startAgent();

        // Sovereign precompile returns empty (triggers fallback)
        vm.mockCall(
            address(0x000000000000000000000000000000000000080C),
            "",
            abi.encode(bytes32(0))
        );

        uint256 supplyBefore = nft.totalSupply();
        vm.prank(scheduler);
        agent.wakeUp(0);

        assertEq(nft.totalSupply(), supplyBefore + 1);
    }

    /// When the sovereign precompile succeeds, executionCount increments in
    /// the Phase 2 callback, not inline.
    function test_wakeUpWithRealJobId() public {
        _startAgent();

        bytes32 fakeJobId = keccak256("job1");
        vm.mockCall(
            address(0x000000000000000000000000000000000000080C),
            "",
            abi.encode(fakeJobId)
        );

        vm.prank(scheduler);
        agent.wakeUp(0);

        // executionCount not yet incremented — waiting for Phase 2
        assertEq(agent.executionCount(), 0);
        assertEq(agent.sovereignJobId(), fakeJobId);
    }

    // ── SovereignJobFailed event ──────────────────────────────────────────────

    function test_sovereignJobFailedEmittedOnRevert() public {
        _startAgent();

        // Make the precompile revert
        vm.mockCallRevert(
            address(0x000000000000000000000000000000000000080C),
            "",
            "precompile reverted"
        );

        vm.expectEmit(false, false, false, true);
        emit AutoMintAgent.SovereignJobFailed("precompile call reverted");

        vm.prank(scheduler);
        agent.wakeUp(0);
    }

    // ── Phase 2 callback ──────────────────────────────────────────────────────

    function test_onlyAsyncDeliveryCanCallback() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(AutoMintAgent.NotAsyncDelivery.selector);
        agent.onSovereignAgentResult(bytes32(0), bytes(""));
    }

    function test_callbackIsIdempotent() public {
        _startAgent();
        bytes32 fakeJobId = keccak256("job-idem");

        // Plant the job id in storage
        vm.store(address(agent), bytes32(uint256(17)), fakeJobId); // sovereignJobId slot

        bytes memory result = _buildSuccessResult();

        vm.startPrank(asyncDelivery);
        agent.onSovereignAgentResult(fakeJobId, result);
        agent.onSovereignAgentResult(fakeJobId, result); // second call must be no-op
        vm.stopPrank();

        assertEq(agent.executionCount(), 1); // incremented exactly once
    }

    function test_callbackIncrementsCountOnSuccess() public {
        _startAgent();
        bytes32 fakeJobId = keccak256("job-ok");
        vm.store(address(agent), bytes32(uint256(17)), fakeJobId);

        vm.prank(asyncDelivery);
        agent.onSovereignAgentResult(fakeJobId, _buildSuccessResult());

        assertEq(agent.executionCount(), 1);
        assertEq(agent.sovereignJobId(), bytes32(0));
    }

    function test_callbackHandlesDecodeFailureGracefully() public {
        _startAgent();
        bytes32 fakeJobId = keccak256("job-bad");
        vm.store(address(agent), bytes32(uint256(17)), fakeJobId);

        vm.prank(asyncDelivery);
        // Pass garbage bytes — should not revert; success=false
        agent.onSovereignAgentResult(fakeJobId, bytes("garbage"));

        assertEq(agent.executionCount(), 1);
    }

    // ── Condition check ───────────────────────────────────────────────────────

    function test_conditionFailedEventEmitted() public {
        SupplyGateCondition gate = new SupplyGateCondition(0); // always false

        bytes memory mintArgs = abi.encode(owner, uint256(1));
        vm.prank(owner);
        address condAgentAddr = factory.createAgent(address(nft), MINT_SELECTOR, mintArgs, 50, 5, address(gate));
        AutoMintAgent condAgent = AutoMintAgent(payable(condAgentAddr));

        vm.prank(owner);
        condAgent.initExecutor();
        vm.prank(owner);
        condAgent.start(0);

        vm.expectEmit(true, false, false, true);
        emit AutoMintAgent.ConditionFailed(0, address(gate));

        vm.prank(scheduler);
        condAgent.wakeUp(0);

        assertEq(condAgent.executionCount(), 0);
    }

    // ── Withdraw ──────────────────────────────────────────────────────────────

    function test_withdrawSendsBalance() public {
        vm.deal(address(agent), 1 ether);
        uint256 balBefore = owner.balance;
        vm.prank(owner);
        agent.withdraw();
        assertEq(owner.balance, balBefore + 1 ether);
    }

    function test_onlyOwnerCanWithdraw() public {
        vm.prank(makeAddr("hacker"));
        vm.expectRevert(AutoMintAgent.NotOwner.selector);
        agent.withdraw();
    }

    // ── UpdateParams ──────────────────────────────────────────────────────────

    function test_updateParamsWhenPaused() public {
        vm.startPrank(owner);
        agent.pause();
        agent.updateParams(address(nft), MINT_SELECTOR, bytes(""), 200, 20, address(0));
        vm.stopPrank();
        assertEq(agent.interval(), 200);
        assertEq(agent.maxExecutions(), 20);
    }

    function test_cannotUpdateWhenRunning() public {
        _startAgent();
        vm.prank(owner);
        vm.expectRevert(AutoMintAgent.NotPausedOrStopped.selector);
        agent.updateParams(address(nft), MINT_SELECTOR, bytes(""), 200, 20, address(0));
    }

    // ── NFT Transfer ──────────────────────────────────────────────────────────

    function test_ownerCanTransferNFTOut() public {
        nft.mint(address(agent), 1);
        uint256 tokenId = nft.totalSupply();
        vm.prank(owner);
        agent.transferNFT(address(nft), tokenId, owner);
        assertEq(nft.ownerOf(tokenId), owner);
    }

    // ── getStatus ─────────────────────────────────────────────────────────────

    function test_getStatus() public {
        _startAgent();
        (bool running, bool _paused, uint32 count, uint32 max, bool condMet, address exec) = agent.getStatus();
        assertTrue(running);
        assertFalse(_paused);
        assertEq(count, 0);
        assertEq(max, 5);
        assertTrue(condMet);
        assertEq(exec, mockExecutor);
    }

    // ── ERC721 receiver ───────────────────────────────────────────────────────

    function test_agentReceivesNFTs() public {
        nft.mint(address(agent), 1);
        assertEq(nft.balanceOf(address(agent)), 1);
    }

    // ── Fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_executionLimitEnforced(uint32 maxExec) public {
        vm.assume(maxExec > 0 && maxExec <= 50);

        bytes memory mintArgs = abi.encode(owner, uint256(1));
        vm.prank(owner);
        address agentAddr = factory.createAgent(address(nft), MINT_SELECTOR, mintArgs, 1, maxExec, address(0));
        AutoMintAgent a = AutoMintAgent(payable(agentAddr));

        vm.prank(owner);
        a.initExecutor();
        vm.prank(owner);
        a.start(0);

        // Sovereign precompile returns zero jobId → fallback to direct mint
        vm.mockCall(address(0x000000000000000000000000000000000000080C), "", abi.encode(bytes32(0)));

        for (uint32 i = 0; i < maxExec; i++) {
            if (!a.isRunning()) break;
            vm.prank(scheduler);
            a.wakeUp(i);
        }

        assertEq(a.executionCount(), maxExec);
        assertFalse(a.isRunning());
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// Build a valid Phase 2 result envelope with success=true.
    function _buildSuccessResult() internal pure returns (bytes memory) {
        // Inner: (bool success, string error, string text, ...) — encode just the bool true
        // We only need the first 32 bytes to be bool true; rest can be minimal.
        bytes memory inner = abi.encode(
            true,
            "",
            "mint executed",
            abi.encode("", "", ""),  // convoHistory StorageRef (simplified)
            abi.encode("", "", "")   // output StorageRef (simplified)
        );
        // Outer envelope: (bytes simmedInput, bytes actualOutput)
        return abi.encode(bytes(""), inner);
    }
}

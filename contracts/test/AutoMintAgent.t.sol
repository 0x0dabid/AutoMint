// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AutoMintAgent} from "../src/AutoMintAgent.sol";
import {AutoMintFactory} from "../src/AutoMintFactory.sol";
import {SampleNFT} from "../src/SampleNFT.sol";
import {SupplyGateCondition, PriceGateCondition, TimeGateCondition} from "../src/MintConditions.sol";

contract AutoMintAgentTest is Test {
    AutoMintFactory internal factory;
    AutoMintAgent internal agent;
    SampleNFT internal nft;

    address internal owner = makeAddr("owner");
    address internal scheduler = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address internal heartbeat = 0xEF505E801f1Db392B5289690E2ffc20e840A3aCa;
    address internal asyncDelivery = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address internal ritualWallet = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;

    bytes4 constant MINT_SELECTOR = SampleNFT.mint.selector;

    function setUp() public {
        factory = new AutoMintFactory();
        nft = new SampleNFT("TestNFT", "TNFT", 1000, 0, 100);

        // Mock system contracts so calls don't revert
        vm.mockCall(scheduler, abi.encodeWithSignature("schedule((address,bytes4,bytes,uint32,uint32,address))"), abi.encode(bytes32(uint256(1))));
        vm.mockCall(scheduler, abi.encodeWithSignature("cancel(bytes32)"), abi.encode());
        vm.mockCall(heartbeat, abi.encodeWithSignature("register(string)"), abi.encode());
        vm.mockCall(heartbeat, abi.encodeWithSignature("beat(string)"), abi.encode());
        vm.mockCall(heartbeat, abi.encodeWithSignature("deregister()"), abi.encode());
        vm.mockCall(ritualWallet, abi.encodeWithSignature("deposit(address)"), abi.encode());
        vm.mockCall(ritualWallet, abi.encodeWithSignature("emergencyWithdraw(address)"), abi.encode());

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

    // ── Start / Cancel ────────────────────────────────────────────────────────

    function test_onlyOwnerCanStart() public {
        vm.prank(makeAddr("hacker"));
        vm.expectRevert(AutoMintAgent.NotOwner.selector);
        agent.start(0);
    }

    function test_startSetsRunning() public {
        vm.prank(owner);
        agent.start(0);
        assertTrue(agent.isRunning());
    }

    function test_cannotStartTwice() public {
        vm.prank(owner);
        agent.start(0);

        vm.prank(owner);
        vm.expectRevert(AutoMintAgent.AlreadyRunning.selector);
        agent.start(0);
    }

    function test_cancelStopsAgent() public {
        vm.prank(owner);
        agent.start(0);

        vm.prank(owner);
        agent.cancel();
        assertFalse(agent.isRunning());
    }

    // ── Pause / Resume ────────────────────────────────────────────────────────

    function test_pauseAndResume() public {
        vm.startPrank(owner);
        agent.start(0);
        agent.pause();
        assertTrue(agent.paused());
        agent.resume();
        assertFalse(agent.paused());
        vm.stopPrank();
    }

    function test_pausedAgentCannotStart() public {
        vm.startPrank(owner);
        agent.pause();
        vm.expectRevert(AutoMintAgent.Paused.selector);
        agent.start(0);
        vm.stopPrank();
    }

    // ── WakeUp (Scheduler callback) ───────────────────────────────────────────

    function test_onlySchedulerCanCallWakeUp() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(AutoMintAgent.NotScheduler.selector);
        agent.wakeUp(0);
    }

    function test_wakeUpExecutesMintDirectly() public {
        // With no TEE precompile mocked, falls back to direct mint
        vm.prank(owner);
        agent.start(0);

        // Mock the persistent agent precompile to return nothing
        vm.mockCall(
            address(0x000000000000000000000000000000000000080C),
            abi.encodeWithSignature("submitJob((string,bytes,uint256,address,bytes4))"),
            abi.encode(bytes32(0)) // empty — triggers fallback
        );

        // Simulate Scheduler calling wakeUp
        uint256 balanceBefore = nft.totalSupply();
        vm.prank(scheduler);
        agent.wakeUp(0);

        // Direct mint path — NFT total supply should increase
        assertEq(nft.totalSupply(), balanceBefore + 1);
    }

    function test_wakeUpDoesNothingWhenPaused() public {
        vm.startPrank(owner);
        agent.start(0);
        agent.pause();
        vm.stopPrank();

        vm.prank(scheduler);
        agent.wakeUp(0); // should not revert, just return early

        assertEq(agent.executionCount(), 0);
    }

    function test_wakeUpDoesNothingWhenNotRunning() public {
        vm.prank(scheduler);
        agent.wakeUp(0);
        assertEq(agent.executionCount(), 0);
    }

    // ── Condition check ───────────────────────────────────────────────────────

    function test_wakeUpSkipsWhenConditionFalse() public {
        // Supply gate with maxSupply=0 — always false
        SupplyGateCondition gate = new SupplyGateCondition(0);

        bytes memory mintArgs = abi.encode(owner, uint256(1));
        vm.prank(owner);
        address condAgentAddr = factory.createAgent(address(nft), MINT_SELECTOR, mintArgs, 50, 5, address(gate));
        AutoMintAgent condAgent = AutoMintAgent(payable(condAgentAddr));

        vm.prank(owner);
        condAgent.start(0);

        vm.prank(scheduler);
        condAgent.wakeUp(0);

        // No mint should have happened — executionCount stays 0
        assertEq(condAgent.executionCount(), 0);
    }

    function test_wakeUpMintsWhenConditionTrue() public {
        // Supply gate with maxSupply=1000 — always true (nft has 0 minted)
        SupplyGateCondition gate = new SupplyGateCondition(1000);

        bytes memory mintArgs = abi.encode(owner, uint256(1));
        vm.prank(owner);
        address condAgentAddr = factory.createAgent(address(nft), MINT_SELECTOR, mintArgs, 50, 5, address(gate));
        AutoMintAgent condAgent = AutoMintAgent(payable(condAgentAddr));

        vm.mockCall(
            address(0x000000000000000000000000000000000000080C),
            abi.encodeWithSignature("submitJob((string,bytes,uint256,address,bytes4))"),
            abi.encode(bytes32(0))
        );

        vm.prank(owner);
        condAgent.start(0);

        vm.prank(scheduler);
        condAgent.wakeUp(0);

        assertEq(condAgent.executionCount(), 1);
    }

    // ── Sovereign Agent callback ───────────────────────────────────────────────

    function test_onlyAsyncDeliveryCanCallback() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(AutoMintAgent.NotAsyncDelivery.selector);
        agent.onSovereignAgentResult(bytes32(0), bytes(""));
    }

    function test_sovereignAgentResultIncrementsCount() public {
        vm.prank(owner);
        agent.start(0);

        // Manually set a sovereignJobId via direct storage manipulation
        bytes32 fakeJobId = keccak256("testjob");
        vm.store(address(agent), bytes32(uint256(16)), fakeJobId); // slot for sovereignJobId

        vm.prank(asyncDelivery);
        agent.onSovereignAgentResult(fakeJobId, hex"01"); // success result

        assertEq(agent.executionCount(), 1);
    }

    // ── Withdraw ──────────────────────────────────────────────────────────────

    function test_withdrawSendsBalance() public {
        vm.deal(address(agent), 1 ether);

        uint256 balBefore = owner.balance;
        vm.prank(owner);
        agent.withdraw();

        assertEq(owner.balance, balBefore + 1 ether);
        assertEq(address(agent).balance, 0);
    }

    function test_onlyOwnerCanWithdraw() public {
        vm.prank(makeAddr("hacker"));
        vm.expectRevert(AutoMintAgent.NotOwner.selector);
        agent.withdraw();
    }

    // ── NFT Transfer ──────────────────────────────────────────────────────────

    function test_ownerCanTransferNFTOut() public {
        // Mint an NFT directly to agent
        nft.mint(address(agent), 1);
        uint256 tokenId = nft.totalSupply();

        vm.prank(owner);
        agent.transferNFT(address(nft), tokenId, owner);

        assertEq(nft.ownerOf(tokenId), owner);
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
        vm.startPrank(owner);
        agent.start(0);
        vm.expectRevert("Agent: must be paused or stopped");
        agent.updateParams(address(nft), MINT_SELECTOR, bytes(""), 200, 20, address(0));
        vm.stopPrank();
    }

    // ── Get status ────────────────────────────────────────────────────────────

    function test_getStatus() public {
        vm.prank(owner);
        agent.start(0);

        (bool running, bool _paused, uint32 count, uint32 max, bool condMet) = agent.getStatus();
        assertTrue(running);
        assertFalse(_paused);
        assertEq(count, 0);
        assertEq(max, 5);
        assertTrue(condMet); // no condition = always true
    }

    // ── ERC721 receiver ───────────────────────────────────────────────────────

    function test_agentReceivesNFTs() public {
        nft.mint(address(agent), 1);
        assertEq(nft.balanceOf(address(agent)), 1);
    }

    // ── Fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_executionLimitEnforced(uint32 maxExec) public {
        vm.assume(maxExec > 0 && maxExec <= 50);

        vm.prank(owner);
        bytes memory mintArgs = abi.encode(owner, uint256(1));
        address agentAddr = factory.createAgent(address(nft), MINT_SELECTOR, mintArgs, 1, maxExec, address(0));
        AutoMintAgent a = AutoMintAgent(payable(agentAddr));

        vm.mockCall(
            address(0x000000000000000000000000000000000000080C),
            abi.encodeWithSignature("submitJob((string,bytes,uint256,address,bytes4))"),
            abi.encode(bytes32(0))
        );

        vm.prank(owner);
        a.start(0);

        // Execute up to maxExec times
        for (uint32 i = 0; i < maxExec; i++) {
            if (!a.isRunning()) break;
            vm.prank(scheduler);
            a.wakeUp(i);
        }

        assertEq(a.executionCount(), maxExec);
        assertFalse(a.isRunning());
    }
}

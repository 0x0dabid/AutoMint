// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AutoMintFactory} from "../src/AutoMintFactory.sol";
import {AutoMintAgent} from "../src/AutoMintAgent.sol";
import {SampleNFT} from "../src/SampleNFT.sol";

contract AutoMintFactoryTest is Test {
    AutoMintFactory internal factory;
    SampleNFT internal nft;

    address internal owner = makeAddr("owner");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");

    function setUp() public {
        factory = new AutoMintFactory();
        nft = new SampleNFT("TestNFT", "TNFT", 1000, 0.01 ether, 10);
    }

    // ── Factory deployment ────────────────────────────────────────────────────

    function test_factoryDeployment() public view {
        assertNotEq(factory.agentImplementation(), address(0));
        assertEq(factory.defaultInterval(), 100);
        assertEq(factory.defaultMaxExecutions(), 10);
    }

    function test_createAgent() public {
        bytes memory mintArgs = abi.encode(user1, uint256(1));
        bytes4 mintSelector = SampleNFT.mint.selector;

        vm.prank(user1);
        address agent = factory.createAgent(
            address(nft),
            mintSelector,
            mintArgs,
            50,  // interval
            5,   // maxExecutions
            address(0)
        );

        assertNotEq(agent, address(0));
        assertEq(factory.agentOwner(agent), user1);

        address[] memory agents = factory.getUserAgents(user1);
        assertEq(agents.length, 1);
        assertEq(agents[0], agent);
    }

    function test_createMultipleAgents() public {
        bytes memory mintArgs = abi.encode(user1, uint256(1));
        bytes4 mintSelector = SampleNFT.mint.selector;

        vm.startPrank(user1);
        factory.createAgent(address(nft), mintSelector, mintArgs, 50, 5, address(0));
        factory.createAgent(address(nft), mintSelector, mintArgs, 100, 10, address(0));
        vm.stopPrank();

        address[] memory agents = factory.getUserAgents(user1);
        assertEq(agents.length, 2);
        assertEq(factory.totalAgents(), 2);
    }

    function test_agentIsInitialized() public {
        bytes memory mintArgs = abi.encode(user1, uint256(1));
        bytes4 mintSelector = SampleNFT.mint.selector;

        vm.prank(user1);
        address agentAddr = factory.createAgent(address(nft), mintSelector, mintArgs, 50, 5, address(0));

        AutoMintAgent agent = AutoMintAgent(payable(agentAddr));
        assertEq(agent.owner(), user1);
        assertEq(agent.nftContract(), address(nft));
        assertEq(agent.mintSelector(), mintSelector);
        assertEq(agent.interval(), 50);
        assertEq(agent.maxExecutions(), 5);
        assertEq(agent.executionCount(), 0);
        assertFalse(agent.isRunning());
        assertFalse(agent.paused());
    }

    function test_createAgentUsesDefaults() public {
        vm.prank(user1);
        address agentAddr = factory.createAgent(
            address(nft), SampleNFT.mint.selector, bytes(""), 0, 0, address(0)
        );

        AutoMintAgent agent = AutoMintAgent(payable(agentAddr));
        assertEq(agent.interval(), factory.defaultInterval());
        assertEq(agent.maxExecutions(), factory.defaultMaxExecutions());
    }

    function test_emitsAgentCreatedEvent() public {
        bytes memory mintArgs = abi.encode(user1, uint256(1));

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit AutoMintFactory.AgentCreated(user1, address(0), address(nft), 5);
        factory.createAgent(address(nft), SampleNFT.mint.selector, mintArgs, 50, 5, address(0));
    }

    function test_pausePreventAgentCreation() public {
        factory.pause();

        vm.prank(user1);
        vm.expectRevert();
        factory.createAgent(address(nft), SampleNFT.mint.selector, bytes(""), 50, 5, address(0));
    }

    function test_unpauseAllowsAgentCreation() public {
        factory.pause();
        factory.unpause();

        vm.prank(user1);
        address agent = factory.createAgent(address(nft), SampleNFT.mint.selector, bytes(""), 50, 5, address(0));
        assertNotEq(agent, address(0));
    }

    function test_onlyOwnerCanSetDefaults() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.setDefaults(200, 20);
    }

    function test_setDefaults() public {
        factory.setDefaults(200, 20);
        assertEq(factory.defaultInterval(), 200);
        assertEq(factory.defaultMaxExecutions(), 20);
    }

    // ── Different users get isolated agents ───────────────────────────────────

    function test_twoUsersGetSeparateAgents() public {
        vm.prank(user1);
        factory.createAgent(address(nft), SampleNFT.mint.selector, bytes(""), 50, 5, address(0));

        vm.prank(user2);
        factory.createAgent(address(nft), SampleNFT.mint.selector, bytes(""), 50, 5, address(0));

        assertEq(factory.getUserAgents(user1).length, 1);
        assertEq(factory.getUserAgents(user2).length, 1);
        assertEq(factory.totalAgents(), 2);

        assertNotEq(factory.getUserAgents(user1)[0], factory.getUserAgents(user2)[0]);
    }

    // ── Fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_createAgentParams(uint32 interval, uint32 maxExec) public {
        vm.assume(interval > 0 && interval < 10000);
        vm.assume(maxExec > 0 && maxExec < 10000);

        vm.prank(user1);
        address agentAddr = factory.createAgent(
            address(nft), SampleNFT.mint.selector, bytes(""), interval, maxExec, address(0)
        );

        AutoMintAgent agent = AutoMintAgent(payable(agentAddr));
        assertEq(agent.interval(), interval);
        assertEq(agent.maxExecutions(), maxExec);
    }
}

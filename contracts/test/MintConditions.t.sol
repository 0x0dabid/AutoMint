// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    SupplyGateCondition,
    PriceGateCondition,
    TimeGateCondition,
    CompositeCondition
} from "../src/MintConditions.sol";
import {SampleNFT} from "../src/SampleNFT.sol";
import {IMintCondition} from "../src/interfaces/IMintCondition.sol";

contract MintConditionsTest is Test {
    SampleNFT internal nft;
    address internal minter = makeAddr("minter");

    function setUp() public {
        nft = new SampleNFT("TestNFT", "TNFT", 100, 0.01 ether, 10);
    }

    // ── SupplyGate ────────────────────────────────────────────────────────────

    function test_supplyGateTrueWhenBelowMax() public {
        SupplyGateCondition gate = new SupplyGateCondition(100);
        assertTrue(gate.shouldMint(address(nft), minter));
    }

    function test_supplyGateFalseWhenAtMax() public {
        SupplyGateCondition gate = new SupplyGateCondition(0);
        assertFalse(gate.shouldMint(address(nft), minter));
    }

    function test_supplyGateFalseAfterMinting() public {
        SupplyGateCondition gate = new SupplyGateCondition(1);
        nft.mint{value: 0.01 ether}(minter, 1);
        assertFalse(gate.shouldMint(address(nft), minter));
    }

    function testFuzz_supplyGate(uint256 maxSup) public {
        vm.assume(maxSup < 1000);
        SupplyGateCondition gate = new SupplyGateCondition(maxSup);
        // nft.totalSupply() == 0, so should mint iff maxSup > 0
        assertEq(gate.shouldMint(address(nft), minter), maxSup > 0);
    }

    // ── PriceGate ────────────────────────────────────────────────────────────

    function test_priceGateTrueWhenPriceOk() public {
        PriceGateCondition gate = new PriceGateCondition(0.01 ether);
        assertTrue(gate.shouldMint(address(nft), minter));
    }

    function test_priceGateFalseWhenPriceTooHigh() public {
        // nft.mintPrice = 0.01 ether, user max = 0.005 ether → false
        PriceGateCondition gate = new PriceGateCondition(0.005 ether);
        assertFalse(gate.shouldMint(address(nft), minter));
    }

    function test_priceGateFalseForContractWithoutMintPrice() public {
        PriceGateCondition gate = new PriceGateCondition(1 ether);
        // address(0) has no mintPrice() function → returns false (try/catch)
        assertFalse(gate.shouldMint(address(0), minter));
    }

    // ── TimeGate ─────────────────────────────────────────────────────────────

    function test_timeGateTrueInWindow() public {
        // Set time to 3am UTC = 10800 seconds
        vm.warp(10800);
        TimeGateCondition gate = new TimeGateCondition(7200, 14400); // 2am–4am
        assertTrue(gate.shouldMint(address(nft), minter));
    }

    function test_timeGateFalseOutsideWindow() public {
        vm.warp(0); // midnight — outside 2am-4am window
        TimeGateCondition gate = new TimeGateCondition(7200, 14400);
        assertFalse(gate.shouldMint(address(nft), minter));
    }

    function test_timeGateRevertsInvalidWindow() public {
        vm.expectRevert("TimeGate: invalid window");
        new TimeGateCondition(14400, 7200);
    }

    function test_timeGateRevertsWindowOver24h() public {
        vm.expectRevert("TimeGate: invalid window");
        new TimeGateCondition(0, 90000);
    }

    // ── CompositeCondition ────────────────────────────────────────────────────

    function test_compositeANDAllTrue() public {
        SupplyGateCondition g1 = new SupplyGateCondition(1000);
        PriceGateCondition g2 = new PriceGateCondition(1 ether);
        address[] memory conds = new address[](2);
        conds[0] = address(g1);
        conds[1] = address(g2);
        CompositeCondition comp = new CompositeCondition(conds, CompositeCondition.Logic.AND);
        assertTrue(comp.shouldMint(address(nft), minter));
    }

    function test_compositeANDOneFalse() public {
        SupplyGateCondition g1 = new SupplyGateCondition(0); // false
        PriceGateCondition g2 = new PriceGateCondition(1 ether); // true
        address[] memory conds = new address[](2);
        conds[0] = address(g1);
        conds[1] = address(g2);
        CompositeCondition comp = new CompositeCondition(conds, CompositeCondition.Logic.AND);
        assertFalse(comp.shouldMint(address(nft), minter));
    }

    function test_compositeOROneTrue() public {
        SupplyGateCondition g1 = new SupplyGateCondition(0); // false
        PriceGateCondition g2 = new PriceGateCondition(1 ether); // true
        address[] memory conds = new address[](2);
        conds[0] = address(g1);
        conds[1] = address(g2);
        CompositeCondition comp = new CompositeCondition(conds, CompositeCondition.Logic.OR);
        assertTrue(comp.shouldMint(address(nft), minter));
    }

    function test_compositeORAllFalse() public {
        SupplyGateCondition g1 = new SupplyGateCondition(0);
        PriceGateCondition g2 = new PriceGateCondition(0);
        address[] memory conds = new address[](2);
        conds[0] = address(g1);
        conds[1] = address(g2);
        CompositeCondition comp = new CompositeCondition(conds, CompositeCondition.Logic.OR);
        assertFalse(comp.shouldMint(address(nft), minter));
    }

    function test_compositeRevertsEmpty() public {
        address[] memory empty = new address[](0);
        vm.expectRevert("CompositeCondition: empty");
        new CompositeCondition(empty, CompositeCondition.Logic.AND);
    }
}

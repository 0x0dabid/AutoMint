// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SampleNFT} from "../src/SampleNFT.sol";

contract SampleNFTTest is Test {
    SampleNFT internal nft;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        nft = new SampleNFT("TestNFT", "TNFT", 10, 0.01 ether, 3);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_mintSuccess() public {
        vm.prank(alice);
        nft.mint{value: 0.01 ether}(alice, 1);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.totalSupply(), 1);
    }

    function test_mintBatch() public {
        vm.prank(alice);
        nft.mint{value: 0.03 ether}(alice, 3);
        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.totalSupply(), 3);
    }

    function test_mintRevertsInsufficientPayment() public {
        vm.prank(alice);
        vm.expectRevert(SampleNFT.InsufficientPayment.selector);
        nft.mint{value: 0.005 ether}(alice, 1);
    }

    function test_mintRevertsSupplyExhausted() public {
        vm.prank(alice);
        nft.mint{value: 0.1 ether}(alice, 10); // fills maxSupply=10

        vm.prank(bob);
        vm.expectRevert(SampleNFT.SupplyExhausted.selector);
        nft.mint{value: 0.01 ether}(bob, 1);
    }

    function test_mintRevertsWalletLimit() public {
        vm.prank(alice);
        vm.expectRevert(SampleNFT.WalletLimitReached.selector);
        nft.mint{value: 0.04 ether}(alice, 4); // limit is 3
    }

    function test_ownerCanWithdraw() public {
        vm.prank(alice);
        nft.mint{value: 0.01 ether}(alice, 1);
        assertEq(address(nft).balance, 0.01 ether);

        uint256 beforeBal = address(this).balance;
        nft.withdraw();
        assertEq(address(this).balance, beforeBal + 0.01 ether);
    }

    function testFuzz_mintQuantity(uint256 qty) public {
        vm.assume(qty > 0 && qty <= 3); // within perWallet limit
        uint256 payment = 0.01 ether * qty;
        vm.deal(alice, payment);
        vm.prank(alice);
        nft.mint{value: payment}(alice, qty);
        assertEq(nft.balanceOf(alice), qty);
    }
}

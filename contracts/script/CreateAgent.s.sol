// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AutoMintFactory} from "../src/AutoMintFactory.sol";
import {AutoMintAgent} from "../src/AutoMintAgent.sol";
import {SampleNFT} from "../src/SampleNFT.sol";

// Example: create an agent and start it
// Usage:
//   FACTORY=<addr> NFT=<addr> forge script script/CreateAgent.s.sol \
//     --rpc-url ritual --private-key $PRIVATE_KEY --broadcast
contract CreateAgent is Script {
    function run() external {
        address factoryAddr = vm.envAddress("FACTORY");
        address nftAddr = vm.envAddress("NFT");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(pk);

        vm.startBroadcast(pk);

        AutoMintFactory factory = AutoMintFactory(factoryAddr);

        // Encode mint(address to, uint256 quantity)
        bytes4 mintSelector = SampleNFT.mint.selector;
        bytes memory mintArgs = abi.encode(user, uint256(1));

        address agentAddr = factory.createAgent(
            nftAddr,
            mintSelector,
            mintArgs,
            200,       // interval: every 200 blocks
            50,        // maxExecutions: 50 mints
            address(0) // no condition
        );

        console.log("Agent deployed at:", agentAddr);

        // Fund agent and start
        AutoMintAgent agent = AutoMintAgent(payable(agentAddr));

        // Deposit 0.1 RITUAL for gas / mint fees
        (bool ok,) = agentAddr.call{value: 0.1 ether}("");
        require(ok, "deposit failed");

        agent.start(10); // start after 10 blocks

        console.log("Agent started! Running:", agent.isRunning());

        vm.stopBroadcast();
    }
}

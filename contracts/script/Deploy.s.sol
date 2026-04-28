// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AutoMintFactory} from "../src/AutoMintFactory.sol";
import {SampleNFT} from "../src/SampleNFT.sol";
import {SupplyGateCondition, PriceGateCondition, TimeGateCondition} from "../src/MintConditions.sol";

contract Deploy is Script {
    // ── Ritual Chain constants ────────────────────────────────────────────────
    uint256 constant RITUAL_CHAIN_ID = 1979;

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        console.log("Deploying on chain:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPk);

        // 1. Deploy AutoMintFactory (deploys agent implementation internally)
        AutoMintFactory factory = new AutoMintFactory();
        console.log("AutoMintFactory:", address(factory));
        console.log("AutoMintAgent implementation:", factory.agentImplementation());

        // 2. Deploy SampleNFT for testing
        SampleNFT sampleNFT = new SampleNFT(
            "AutoMint Sample",
            "AMS",
            10_000,      // maxSupply
            0.001 ether, // mintPrice (0.001 RITUAL)
            20           // maxPerWallet
        );
        console.log("SampleNFT:", address(sampleNFT));

        // 3. Deploy condition presets
        SupplyGateCondition supplyGate = new SupplyGateCondition(9_000);
        console.log("SupplyGateCondition (max 9000):", address(supplyGate));

        PriceGateCondition priceGate = new PriceGateCondition(0.01 ether);
        console.log("PriceGateCondition (max 0.01 RITUAL):", address(priceGate));

        TimeGateCondition timeGate = new TimeGateCondition(7200, 14400); // 2am-4am UTC
        console.log("TimeGateCondition (2am-4am UTC):", address(timeGate));

        vm.stopBroadcast();

        // Write deployment summary
        _writeSummary(address(factory), address(sampleNFT), address(supplyGate), address(priceGate), address(timeGate));
    }

    function _writeSummary(
        address factory,
        address sampleNFT,
        address supplyGate,
        address priceGate,
        address timeGate
    ) internal {
        string memory json = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"factory":"',
            vm.toString(factory),
            '","sampleNFT":"',
            vm.toString(sampleNFT),
            '","conditions":{"supplyGate":"',
            vm.toString(supplyGate),
            '","priceGate":"',
            vm.toString(priceGate),
            '","timeGate":"',
            vm.toString(timeGate),
            '"}}'
        );
        vm.writeFile("deployments.json", json);
        console.log("\nDeployment summary written to deployments.json");
    }
}

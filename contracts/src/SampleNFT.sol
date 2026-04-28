// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SampleNFT is ERC721, Ownable {
    uint256 public totalSupply;
    uint256 public maxSupply;
    uint256 public mintPrice;
    uint256 public maxPerWallet;

    mapping(address => uint256) public mintedByWallet;

    event Minted(address indexed to, uint256 indexed tokenId);

    error SupplyExhausted();
    error WalletLimitReached();
    error InsufficientPayment();

    constructor(string memory name, string memory symbol, uint256 _maxSupply, uint256 _mintPrice, uint256 _maxPerWallet)
        ERC721(name, symbol)
        Ownable(msg.sender)
    {
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        maxPerWallet = _maxPerWallet;
    }

    function mint(address to, uint256 quantity) external payable {
        if (totalSupply + quantity > maxSupply) revert SupplyExhausted();
        if (mintedByWallet[to] + quantity > maxPerWallet) revert WalletLimitReached();
        if (msg.value < mintPrice * quantity) revert InsufficientPayment();

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = ++totalSupply;
            mintedByWallet[to]++;
            _mint(to, tokenId);
            emit Minted(to, tokenId);
        }
    }

    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }

    function setMaxPerWallet(uint256 _max) external onlyOwner {
        maxPerWallet = _max;
    }

    function withdraw() external onlyOwner {
        (bool ok,) = owner().call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }
}

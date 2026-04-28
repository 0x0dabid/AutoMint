// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMintCondition} from "./interfaces/IMintCondition.sol";

interface IERC721Supply {
    function totalSupply() external view returns (uint256);

    function maxSupply() external view returns (uint256);
}

interface IMintPrice {
    function mintPrice() external view returns (uint256);
}

// Passes only when totalSupply < threshold
contract SupplyGateCondition is IMintCondition {
    uint256 public immutable maxSupply;

    constructor(uint256 _maxSupply) {
        maxSupply = _maxSupply;
    }

    function shouldMint(address nftContract, address) external view override returns (bool) {
        try IERC721Supply(nftContract).totalSupply() returns (uint256 supply) {
            return supply < maxSupply;
        } catch {
            return false;
        }
    }
}

// Passes only when current mint price <= user's max price
contract PriceGateCondition is IMintCondition {
    uint256 public immutable maxPrice;

    constructor(uint256 _maxPrice) {
        maxPrice = _maxPrice;
    }

    function shouldMint(address nftContract, address) external view override returns (bool) {
        try IMintPrice(nftContract).mintPrice() returns (uint256 price) {
            return price <= maxPrice;
        } catch {
            return false;
        }
    }
}

// Passes only within a UTC time window (timestamp range)
contract TimeGateCondition is IMintCondition {
    uint256 public immutable windowStart; // seconds since midnight UTC
    uint256 public immutable windowEnd; // seconds since midnight UTC

    constructor(uint256 _windowStart, uint256 _windowEnd) {
        require(_windowStart < _windowEnd && _windowEnd <= 86400, "TimeGate: invalid window");
        windowStart = _windowStart;
        windowEnd = _windowEnd;
    }

    function shouldMint(address, address) external view override returns (bool) {
        uint256 timeOfDay = block.timestamp % 86400;
        return timeOfDay >= windowStart && timeOfDay < windowEnd;
    }
}

// Combines multiple conditions with AND or OR logic
contract CompositeCondition is IMintCondition {
    enum Logic {
        AND,
        OR
    }

    address[] public conditions;
    Logic public logic;

    constructor(address[] memory _conditions, Logic _logic) {
        require(_conditions.length > 0, "CompositeCondition: empty");
        conditions = _conditions;
        logic = _logic;
    }

    function shouldMint(address nftContract, address minter) external view override returns (bool) {
        if (logic == Logic.AND) {
            for (uint256 i = 0; i < conditions.length; i++) {
                if (!IMintCondition(conditions[i]).shouldMint(nftContract, minter)) return false;
            }
            return true;
        } else {
            for (uint256 i = 0; i < conditions.length; i++) {
                if (IMintCondition(conditions[i]).shouldMint(nftContract, minter)) return true;
            }
            return false;
        }
    }
}

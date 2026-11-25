// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Mintable ERC20 mock for testnet demos. Decimals configurable at deploy.
/// The deployer (owner) can appoint a minter that may mint and burn on its behalf.
contract MockToken is ERC20, Ownable {
    uint8 private immutable _decimals;
    address public minter;

    event MinterUpdated(address indexed minter);

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setMinter(address minter_) external onlyOwner {
        minter = minter_;
        emit MinterUpdated(minter_);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter || msg.sender == owner(), "not minter");
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        require(msg.sender == minter || msg.sender == owner(), "not minter");
        _burn(from, amount);
    }
}

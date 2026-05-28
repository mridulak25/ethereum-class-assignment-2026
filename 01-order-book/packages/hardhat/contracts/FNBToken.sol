// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // Solidity version for this contract

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // Standard ERC20 implementation from OpenZeppelin

contract FNBToken is ERC20 { // FNBToken inherits standard ERC20 functionality
    constructor(uint256 initialSupply) ERC20("FNB Token", "FNBT") { // Sets name/symbol, takes supply
        _mint(msg.sender, initialSupply); // Mints full supply to the deployer
    }
}

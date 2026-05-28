// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; // Solidity version for this contract

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // Standard ERC20 implementation from OpenZeppelin

contract PNPToken is ERC20 { // PNPToken inherits standard ERC20 functionality
    constructor(uint256 initialSupply) ERC20("PNP Token", "PNPT") { // Constructor takes an initial supply and sets the token name and symbol   
        _mint(msg.sender, initialSupply); // Mints initial supply to the deployer of the contract
    }
}

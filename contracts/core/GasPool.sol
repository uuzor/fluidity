// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/USDF.sol";

/**
 * @title GasPool
 * @dev Holds USDF gas compensation for liquidation operations
 */
contract GasPool is Ownable {
    USDF public usdfToken;
    
    constructor() Ownable(msg.sender) {}
    
    function setUSDF(address _usdfToken) external onlyOwner {
        usdfToken = USDF(_usdfToken);
    }
    
    // This contract simply holds USDF tokens for gas compensation
    // The actual gas compensation is handled by the TroveManager
}
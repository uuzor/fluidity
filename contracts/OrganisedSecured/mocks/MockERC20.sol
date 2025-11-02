// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 ts) ERC20(name, symbol) {
        mint(msg.sender, ts);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Burn from caller's balance (matches IUSDF interface)
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    // Burn from specified address (requires approval)
    function burnFrom(address from, uint256 amount) public {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }
}

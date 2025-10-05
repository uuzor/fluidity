// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FluidVault
 * @dev Individual vault contract for holding assets
 */
contract FluidVault is Ownable {
    using SafeERC20 for IERC20;

    address public immutable asset;
    address public immutable strategy;
    address public immutable manager;

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager");
        _;
    }

    modifier onlyStrategy() {
        require(msg.sender == strategy, "Only strategy");
        _;
    }

    constructor(address _asset, address _strategy, address _manager) Ownable(_manager) {
        asset = _asset;
        strategy = _strategy;
        manager = _manager;
    }

    function transferToStrategy(uint256 amount) external onlyManager {
        IERC20(asset).safeTransfer(strategy, amount);
    }

    function transferFromStrategy(uint256 amount) external onlyStrategy {
        IERC20(asset).safeTransferFrom(strategy, address(this), amount);
    }

    function balance() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function emergencyWithdraw() external onlyManager {
        uint256 balanceAsset = IERC20(asset).balanceOf(address(this));
        if (balanceAsset > 0) {
            IERC20(asset).safeTransfer(manager, balanceAsset);
        }
    }
}
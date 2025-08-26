// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DefaultPool
 * @dev Holds collateral and USDF debt from liquidated troves
 */
contract DefaultPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    mapping(address => uint256) public collateral; // asset => amount
    mapping(address => uint256) public usdfDebt; // asset => debt amount
    
    address public troveManager;
    address public activePool;

    // Events
    event CollateralSent(address indexed asset, address indexed to, uint256 amount);
    event USdfDebtUpdated(address indexed asset, uint256 debt);
    event CollateralReceived(address indexed asset, uint256 amount);

    modifier onlyTroveManager() {
        require(msg.sender == troveManager, "DefaultPool: Caller is not TroveManager");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setAddresses(address _troveManager, address _activePool) external onlyOwner {
        troveManager = _troveManager;
        activePool = _activePool;
    }

    function getCollateral(address asset) external view returns (uint256) {
        return collateral[asset];
    }

    function getUSdfDebt(address asset) external view returns (uint256) {
        return usdfDebt[asset];
    }

    function sendCollateralToActivePool(address asset, uint256 amount) external onlyTroveManager {
        require(amount > 0, "Amount must be greater than 0");
        require(collateral[asset] >= amount, "Insufficient collateral");
        
        collateral[asset] -= amount;
        
        if (asset == address(0)) {
            payable(activePool).transfer(amount);
        } else {
            IERC20(asset).safeTransfer(activePool, amount);
        }
        
        emit CollateralSent(asset, activePool, amount);
    }

    function increaseUSdfDebt(address asset, uint256 amount) external onlyTroveManager {
        usdfDebt[asset] += amount;
        emit USdfDebtUpdated(asset, usdfDebt[asset]);
    }

    function decreaseUSdfDebt(address asset, uint256 amount) external onlyTroveManager {
        require(usdfDebt[asset] >= amount, "Insufficient debt");
        usdfDebt[asset] -= amount;
        emit USdfDebtUpdated(asset, usdfDebt[asset]);
    }

    function pullCollateralFromActivePool(address asset, uint256 amount) external onlyTroveManager {
        collateral[asset] += amount;
        emit CollateralReceived(asset, amount);
    }

    // Allow contract to receive ETH
    receive() external payable {
        if (msg.value > 0) {
            collateral[address(0)] += msg.value;
            emit CollateralReceived(address(0), msg.value);
        }
    }
}
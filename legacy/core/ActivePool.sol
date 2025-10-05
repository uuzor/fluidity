// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ActivePool
 * @dev Holds collateral and USDF debt for all active troves
 */
contract ActivePool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    mapping(address => uint256) public collateral; // asset => amount
    mapping(address => uint256) public usdfDebt; // asset => debt amount
    
    address public borrowerOperations;
    address public troveManager;
    address public stabilityPool;
    address public defaultPool;

    // Events
    event CollateralSent(address indexed asset, address indexed to, uint256 amount);
    event USDBorrowingFeeSent(address indexed to, uint256 amount);
    event CollateralReceived(address indexed asset, uint256 amount);

    modifier onlyBorrowerOperationsOrTroveManager() {
        require(
            msg.sender == borrowerOperations || msg.sender == troveManager,
            "ActivePool: Caller is not BorrowerOperations or TroveManager"
        );
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setAddresses(
        address _borrowerOperations,
        address _troveManager,
        address _stabilityPool,
        address _defaultPool
    ) external onlyOwner {
        borrowerOperations = _borrowerOperations;
        troveManager = _troveManager;
        stabilityPool = _stabilityPool;
        defaultPool = _defaultPool;
    }

    function getCollateral(address asset) external view returns (uint256) {
        return collateral[asset];
    }

    function getUSdfDebt(address asset) external view returns (uint256) {
        return usdfDebt[asset];
    }

    function sendCollateral(address asset, address to, uint256 amount) external onlyBorrowerOperationsOrTroveManager {
        require(amount > 0, "Amount must be greater than 0");
        require(collateral[asset] >= amount, "Insufficient collateral");
        
        collateral[asset] -= amount;
        
        if (asset == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
        
        emit CollateralSent(asset, to, amount);
    }

    function increaseUSdfDebt(address asset, uint256 amount) external onlyBorrowerOperationsOrTroveManager {
        usdfDebt[asset] += amount;
    }

    function decreaseUSdfDebt(address asset, uint256 amount) external onlyBorrowerOperationsOrTroveManager {
        require(usdfDebt[asset] >= amount, "Insufficient debt");
        usdfDebt[asset] -= amount;
    }

    function pullCollateralFromBorrowerOperationsOrDefaultPool(address asset, uint256 amount) external onlyBorrowerOperationsOrTroveManager {
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
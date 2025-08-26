// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CollSurplusPool
 * @dev Holds surplus collateral from liquidations for borrowers to claim
 */
contract CollSurplusPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    mapping(address => mapping(address => uint256)) public balances; // user => asset => amount
    mapping(address => uint256) public totalCollateral; // asset => total amount
    
    address public borrowerOperations;
    address public troveManager;
    address public activePool;

    // Events
    event CollateralReceived(address indexed user, address indexed asset, uint256 amount);
    event CollateralClaimed(address indexed user, address indexed asset, uint256 amount);

    modifier onlyTroveManager() {
        require(msg.sender == troveManager, "CollSurplusPool: Caller is not TroveManager");
        _;
    }

    modifier onlyBorrowerOperations() {
        require(msg.sender == borrowerOperations, "CollSurplusPool: Caller is not BorrowerOperations");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setAddresses(
        address _borrowerOperations,
        address _troveManager,
        address _activePool
    ) external onlyOwner {
        borrowerOperations = _borrowerOperations;
        troveManager = _troveManager;
        activePool = _activePool;
    }

    function getCollateral(address asset) external view returns (uint256) {
        return totalCollateral[asset];
    }

    function getUserCollateral(address user, address asset) external view returns (uint256) {
        return balances[user][asset];
    }

    function accountSurplus(address account, address asset, uint256 amount) external onlyTroveManager {
        require(amount > 0, "Amount must be greater than 0");
        
        balances[account][asset] += amount;
        totalCollateral[asset] += amount;
        
        emit CollateralReceived(account, asset, amount);
    }

    function claimColl(address account, address asset) external onlyBorrowerOperations {
        uint256 claimableCollateral = balances[account][asset];
        require(claimableCollateral > 0, "No collateral to claim");
        
        balances[account][asset] = 0;
        totalCollateral[asset] -= claimableCollateral;
        
        if (asset == address(0)) {
            payable(account).transfer(claimableCollateral);
        } else {
            IERC20(asset).safeTransfer(account, claimableCollateral);
        }
        
        emit CollateralClaimed(account, asset, claimableCollateral);
    }

    // Allow contract to receive ETH
    receive() external payable {
        // ETH received will be tracked when accountSurplus is called
    }
}
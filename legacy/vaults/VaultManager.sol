// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IUnifiedLiquidityPool.sol";
import "../interfaces/IYieldStrategy.sol";
import "../libraries/Math.sol";
import "./FluidVault.sol";

/**
 * @title VaultManager
 * @dev Manages yield strategies and vault operations
 */
contract VaultManager is IVaultManager, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_PERFORMANCE_FEE = 0.3e18; // 30%
    uint256 public constant MAX_MANAGEMENT_FEE = 0.02e18; // 2%
    uint256 public constant MIN_HARVEST_DELAY = 1 hours;
    uint256 public constant MAX_HARVEST_DELAY = 7 days;

    // State variables
    mapping(address => VaultInfo) public vaultInfo;
    mapping(address => StrategyParams) public strategyParams;
    mapping(address => mapping(address => uint256)) public userShares; // user => vault => shares
    mapping(address => address[]) public vaultsByAsset;
    
    address[] public allVaults;
    IUnifiedLiquidityPool public unifiedPool;
    
    // Fee collection
    address public feeRecipient;
    mapping(address => uint256) public collectedFees;
    
    // Performance tracking
    mapping(address => uint256) public lastProfitPerShare;
    mapping(address => uint256) public totalProfitGenerated;

    modifier onlyActiveVault(address vault) {
        require(vaultInfo[vault].isActive, "Vault not active");
        require(!vaultInfo[vault].emergencyExit, "Vault in emergency exit");
        _;
    }

    modifier onlyValidVault(address vault) {
        require(vaultInfo[vault].strategy != address(0), "Invalid vault");
        _;
    }

    constructor(address _unifiedPool, address _feeRecipient) Ownable(msg.sender) {
        unifiedPool = IUnifiedLiquidityPool(_unifiedPool);
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Create a new vault with specified strategy
     */
    function createVault(address strategy, address asset, StrategyParams calldata params) 
        external 
        onlyOwner 
        returns (address vault) 
    {
        require(strategy != address(0), "Invalid strategy");
        require(asset != address(0), "Invalid asset");
        require(params.performanceFee <= MAX_PERFORMANCE_FEE, "Performance fee too high");
        require(params.managementFee <= MAX_MANAGEMENT_FEE, "Management fee too high");
        require(params.harvestDelay >= MIN_HARVEST_DELAY && params.harvestDelay <= MAX_HARVEST_DELAY, "Invalid harvest delay");

        // Deploy new vault contract
        vault = address(new FluidVault(asset, strategy, address(this)));
        
        // Initialize vault info
        vaultInfo[vault] = VaultInfo({
            strategy: strategy,
            asset: asset,
            totalDeposits: 0,
            totalShares: 0,
            performanceFee: params.performanceFee,
            managementFee: params.managementFee,
            lastHarvest: block.timestamp,
            isActive: true,
            emergencyExit: false
        });
        
        strategyParams[vault] = params;
        allVaults.push(vault);
        vaultsByAsset[asset].push(vault);
        
        // Initialize strategy
        IYieldStrategy(strategy).initialize(asset, vault);
        
        emit VaultCreated(vault, strategy, asset);
        return vault;
    }

    /**
     * @dev Update vault strategy
     */
    function updateStrategy(address vault, address newStrategy) external onlyOwner onlyValidVault(vault) {
        require(newStrategy != address(0), "Invalid strategy");
        
        VaultInfo storage info = vaultInfo[vault];
        address oldStrategy = info.strategy;
        
        // Withdraw all funds from old strategy
        if (oldStrategy != address(0)) {
            IYieldStrategy(oldStrategy).withdrawAll();
        }
        
        // Update strategy
        info.strategy = newStrategy;
        IYieldStrategy(newStrategy).initialize(info.asset, vault);
        
        // Deposit funds into new strategy
        uint256 balance = IERC20(info.asset).balanceOf(vault);
        if (balance > 0) {
            IERC20(info.asset).safeTransferFrom(vault, address(this), balance);
            IERC20(info.asset).safeTransfer(newStrategy, balance);
            IYieldStrategy(newStrategy).deposit(balance);
        }
        
        emit StrategyUpdated(vault, oldStrategy, newStrategy);
    }

    /**
     * @dev Set vault parameters
     */
    function setVaultParams(address vault, StrategyParams calldata params) external onlyOwner onlyValidVault(vault) {
        require(params.performanceFee <= MAX_PERFORMANCE_FEE, "Performance fee too high");
        require(params.managementFee <= MAX_MANAGEMENT_FEE, "Management fee too high");
        require(params.harvestDelay >= MIN_HARVEST_DELAY && params.harvestDelay <= MAX_HARVEST_DELAY, "Invalid harvest delay");
        
        strategyParams[vault] = params;
        vaultInfo[vault].performanceFee = params.performanceFee;
        vaultInfo[vault].managementFee = params.managementFee;
    }

    /**
     * @dev Deposit assets into a vault
     */
    function deposit(address vault, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlyActiveVault(vault) 
        returns (uint256 shares) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        VaultInfo storage info = vaultInfo[vault];
        StrategyParams memory params = strategyParams[vault];
        
        require(amount >= params.minDeposit, "Below minimum deposit");
        require(info.totalDeposits + amount <= params.maxDeposit, "Exceeds maximum deposit");
        
        // Transfer tokens from user
        IERC20(info.asset).safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate shares to mint
        if (info.totalShares == 0) {
            shares = amount;
        } else {
            uint256 totalAssets = getVaultTVL(vault);
            shares = amount.mulDiv(info.totalShares, totalAssets);
        }
        
        // Update state
        userShares[msg.sender][vault] += shares;
        info.totalShares += shares;
        info.totalDeposits += amount;
        
        // Deposit into strategy
        IERC20(info.asset).safeTransfer(info.strategy, amount);
        IYieldStrategy(info.strategy).deposit(amount);
        
        emit Deposited(msg.sender, vault, amount, shares);
        return shares;
    }

    /**
     * @dev Withdraw assets from a vault
     */
    function withdraw(address vault, uint256 shares) 
        public 
        nonReentrant 
        onlyValidVault(vault) 
        returns (uint256 amount) 
    {
        require(shares > 0, "Shares must be greater than 0");
        require(userShares[msg.sender][vault] >= shares, "Insufficient shares");
        
        VaultInfo storage info = vaultInfo[vault];
        StrategyParams memory params = strategyParams[vault];
        
        // Calculate amount to withdraw
        uint256 totalAssets = getVaultTVL(vault);
        amount = shares.mulDiv(totalAssets, info.totalShares);
        
        // Apply withdrawal fee if applicable
        uint256 withdrawalFee = 0;
        if (params.withdrawalFee > 0) {
            withdrawalFee = amount.mulDiv(params.withdrawalFee, PRECISION);
            amount -= withdrawalFee;
            collectedFees[info.asset] += withdrawalFee;
        }
        
        // Update state
        userShares[msg.sender][vault] -= shares;
        info.totalShares -= shares;
        info.totalDeposits -= amount;
        
        // Withdraw from strategy
        IYieldStrategy(info.strategy).withdraw(amount + withdrawalFee);
        
        // Transfer to user
        IERC20(info.asset).safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, vault, shares, amount);
        return amount;
    }

    /**
     * @dev Withdraw all user's assets from a vault
     */
    function withdrawAll(address vault) external returns (uint256 amount) {
        uint256 shares = userShares[msg.sender][vault];
        require(shares > 0, "No shares to withdraw");
        return withdraw(vault, shares);
    }

    /**
     * @dev Harvest profits from a strategy
     */
    function harvest(address vault) 
        external 
        nonReentrant 
        onlyValidVault(vault) 
        returns (uint256 profit) 
    {
        require(canHarvest(vault), "Cannot harvest yet");
        
        VaultInfo storage info = vaultInfo[vault];
        uint256 balanceBefore = getStrategyBalance(vault);
        
        // Execute harvest
        profit = IYieldStrategy(info.strategy).harvest();
        
        if (profit > 0) {
            // Calculate fees
            uint256 performanceFee = profit.mulDiv(info.performanceFee, PRECISION);
            uint256 managementFee = getVaultTVL(vault).mulDiv(info.managementFee, PRECISION).mulDiv(
                block.timestamp - info.lastHarvest, 365 days
            );
            
            uint256 totalFees = performanceFee + managementFee;
            collectedFees[info.asset] += totalFees;
            
            // Update tracking
            totalProfitGenerated[vault] += profit;
            lastProfitPerShare[vault] = profit.mulDiv(PRECISION, info.totalShares);
        }
        
        info.lastHarvest = block.timestamp;
        
        emit Harvested(vault, profit, profit > 0 ? profit.mulDiv(info.performanceFee, PRECISION) : 0);
        return profit;
    }

    /**
     * @dev Rebalance vault strategy
     */
    function rebalance(address vault) external onlyOwner onlyValidVault(vault) {
        IYieldStrategy(vaultInfo[vault].strategy).rebalance();
    }

    /**
     * @dev Emergency withdraw all funds from strategy
     */
    function emergencyWithdraw(address vault) external onlyOwner onlyValidVault(vault) {
        VaultInfo storage info = vaultInfo[vault];
        info.emergencyExit = true;
        
        uint256 amount = IYieldStrategy(info.strategy).emergencyWithdraw();
        
        emit EmergencyExit(vault, amount);
    }

    /**
     * @dev Pause a vault
     */
    function pauseVault(address vault) external onlyOwner onlyValidVault(vault) {
        vaultInfo[vault].isActive = false;
    }

    /**
     * @dev Unpause a vault
     */
    function unpauseVault(address vault) external onlyOwner onlyValidVault(vault) {
        vaultInfo[vault].isActive = true;
        vaultInfo[vault].emergencyExit = false;
    }

    // View functions
    function getVaultInfo(address vault) external view returns (VaultInfo memory) {
        return vaultInfo[vault];
    }

    function getUserShares(address user, address vault) external view returns (uint256) {
        return userShares[user][vault];
    }

    function getUserBalance(address user, address vault) external view returns (uint256) {
        uint256 shares = userShares[user][vault];
        if (shares == 0) return 0;
        
        uint256 totalAssets = getVaultTVL(vault);
        return shares.mulDiv(totalAssets, vaultInfo[vault].totalShares);
    }

    function getVaultTVL(address vault) public view returns (uint256) {
        return getStrategyBalance(vault);
    }

    function getVaultAPY(address vault) external view returns (uint256) {
        uint256 totalProfit = totalProfitGenerated[vault];
        uint256 totalDeposits = vaultInfo[vault].totalDeposits;
        
        if (totalDeposits == 0) return 0;
        
        // Simple APY calculation based on historical performance
        uint256 timePeriod = block.timestamp - vaultInfo[vault].lastHarvest;
        if (timePeriod == 0) return 0;
        
        uint256 annualizedReturn = totalProfit.mulDiv(365 days, timePeriod);
        return annualizedReturn.mulDiv(PRECISION, totalDeposits);
    }

    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    function getVaultsByAsset(address asset) external view returns (address[] memory) {
        return vaultsByAsset[asset];
    }

    function getStrategyBalance(address vault) public view returns (uint256) {
        address strategy = vaultInfo[vault].strategy;
        if (strategy == address(0)) return 0;
        return IYieldStrategy(strategy).balanceOf();
    }

    function getStrategyAllocatedAmount(address vault) external view returns (uint256) {
        address strategy = vaultInfo[vault].strategy;
        if (strategy == address(0)) return 0;
        return IYieldStrategy(strategy).getAllocatedAmount();
    }

    function canHarvest(address vault) public view returns (bool) {
        VaultInfo memory info = vaultInfo[vault];
        StrategyParams memory params = strategyParams[vault];
        
        return block.timestamp >= info.lastHarvest + params.harvestDelay;
    }

    // Admin functions
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    function collectFees(address asset) external onlyOwner {
        uint256 fees = collectedFees[asset];
        require(fees > 0, "No fees to collect");
        
        collectedFees[asset] = 0;
        IERC20(asset).safeTransfer(feeRecipient, fees);
    }

    function setUnifiedPool(address _unifiedPool) external onlyOwner {
        unifiedPool = IUnifiedLiquidityPool(_unifiedPool);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
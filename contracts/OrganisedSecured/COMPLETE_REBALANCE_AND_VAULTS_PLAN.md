# Complete Rebalancing & Vaults Implementation Plan

**Date**: October 25, 2025
**Status**: 🚧 IMPLEMENTATION ROADMAP
**Based on**: AMM_ARCHITECTURE_ANALYSIS.md, AMM_LIQUIDATION_FLOW.md, IMPLEMENTATION_COMPLETE.md

---

## 📊 Current State Analysis

### ✅ What's Implemented

1. **CapitalEfficiencyEngine Structure** (653 lines)
   - ✅ Packed struct storage (gas optimized)
   - ✅ Circuit breakers (90% utilization cap)
   - ✅ Cascading withdrawal logic
   - ✅ Security patterns applied (checks-effects-interactions)
   - ✅ Admin functions (activate asset, set config)
   - ✅ View functions (utilization, allocation tracking)

2. **FluidAMM Integration Points**
   - ✅ Interface defined (IFluidAMM)
   - ✅ Emergency withdrawal from AMM
   - ✅ State tracking for allocated amounts

3. **Safety Mechanisms**
   - ✅ 30% reserve buffer requirement
   - ✅ Balance validation before transfers
   - ✅ NonReentrant guards
   - ✅ Access control integration

### ⚠️ What's Missing (TODOs)

#### **CRITICAL (Must Complete for Testnet)**

1. **rebalance() - AMM Liquidity Operations** (Lines 334-393)
   - ❌ Add liquidity when `currentAMM < targetAMM`
   - ❌ Remove liquidity when `currentAMM > targetAMM`
   - ❌ Calculate optimal USDF pairing amount
   - ❌ Slippage protection
   - ❌ LP token tracking

2. **allocateCollateral() - AMM Integration** (Lines 285-299)
   - ❌ Calculate USDF amount for pairing
   - ❌ Call `fluidAMM.addLiquidity()`
   - ❌ Store LP tokens received

3. **emergencyRecallAll() - Return Mechanism** (Lines 533-537)
   - ❌ LiquidityCore function to receive returns
   - ❌ Update LiquidityCore accounting

#### **HIGH PRIORITY (Recommended for Testnet)**

4. **Vault Integration**
   - ❌ IVault interface
   - ❌ Vault withdrawal logic
   - ❌ Vault deposit logic
   - ❌ Yield tracking

5. **Staking Integration**
   - ❌ IStaking interface
   - ❌ Staking withdrawal logic
   - ❌ Unbonding period handling

6. **USDF Token Reference**
   - ❌ Missing USDF token reference in CapitalEfficiencyEngine
   - ❌ Needed for AMM pairing calculations

---

## 🎯 Implementation Strategy

### Phase 1: Complete AMM Integration (Week 1)

#### **Task 1.1: Add USDF Token Reference**

**File**: `CapitalEfficiencyEngine.sol`

```solidity
// Add to immutables section (after line 167)
/// @notice USDF stablecoin token
IERC20 public immutable usdfToken;

// Update constructor (line 194)
constructor(
    address _accessControl,
    address _liquidityCore,
    address _troveManager,
    address _usdfToken  // NEW
) OptimizedSecurityBase(_accessControl) {
    require(_liquidityCore != address(0), "Invalid LiquidityCore");
    require(_troveManager != address(0), "Invalid TroveManager");
    require(_usdfToken != address(0), "Invalid USDF token");

    liquidityCore = ILiquidityCore(_liquidityCore);
    troveManager = ITroveManager(_troveManager);
    usdfToken = IERC20(_usdfToken);  // NEW
}
```

---

#### **Task 1.2: Complete rebalance() Function**

**Location**: Lines 308-401

**Implementation**:

```solidity
function rebalance(address asset)
    external
    override
    nonReentrant
    whenNotPaused
    activeAsset(asset)
{
    if (!shouldRebalance(asset)) {
        revert RebalanceNotNeeded(asset);
    }

    CapitalAllocation storage allocation = _allocations[asset];
    AllocationConfig memory config = _configs[asset];

    // Get current total collateral
    uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);
    allocation.totalCollateral = _toUint128(totalCollateral);

    // Calculate target allocations
    uint256 targetAMM = (totalCollateral * config.ammAllocationPct) / BASIS_POINTS;
    uint256 currentAMM = allocation.allocatedToAMM;

    // === ADD LIQUIDITY TO AMM ===
    if (currentAMM < targetAMM && address(fluidAMM) != address(0)) {
        uint256 toAdd = targetAMM - currentAMM;

        // 1. Verify LiquidityCore has balance (FIX CRIT-1)
        uint256 coreBalance = IERC20(asset).balanceOf(address(liquidityCore));
        require(coreBalance >= toAdd, "Insufficient LiquidityCore balance");

        // 2. Transfer from LiquidityCore to this contract
        liquidityCore.transferCollateral(asset, address(this), toAdd);

        // 3. Calculate optimal USDF amount based on pool reserves
        bytes32 poolId = fluidAMM.getPoolId(asset, address(usdfToken));
        (uint256 reserveAsset, uint256 reserveUSDFL, ) = fluidAMM.getPoolReserves(poolId);

        uint256 usdfAmount;
        if (reserveAsset > 0 && reserveUSDFL > 0) {
            // Pool exists - calculate proportional USDF amount
            usdfAmount = (toAdd * reserveUSDFL) / reserveAsset;
        } else {
            // New pool - use oracle price
            // Assuming 1:1 for simplicity, or query PriceOracle
            uint256 assetPrice = _getAssetPrice(asset);
            usdfAmount = (toAdd * assetPrice) / 1e18;
        }

        // 4. Verify we have enough USDF (need to source this - treasury or mint?)
        uint256 usdfBalance = usdfToken.balanceOf(address(this));
        require(usdfBalance >= usdfAmount, "Insufficient USDF for pairing");

        // 5. Approve AMM to spend both tokens
        IERC20(asset).forceApprove(address(fluidAMM), toAdd);
        usdfToken.forceApprove(address(fluidAMM), usdfAmount);

        // 6. Add liquidity with 5% slippage protection
        uint256 minAsset = (toAdd * 95) / 100;
        uint256 minUSDFL = (usdfAmount * 95) / 100;

        (uint256 amountAsset, uint256 amountUSDFL, uint256 liquidity) = fluidAMM.addLiquidity(
            asset,
            address(usdfToken),
            toAdd,
            usdfAmount,
            minAsset,
            minUSDFL,
            address(this),  // LP tokens to this contract
            block.timestamp + 300  // 5 minute deadline
        );

        // 7. Update tracking
        allocation.allocatedToAMM = _toUint128(uint256(allocation.allocatedToAMM) + amountAsset);
        allocation.lpTokensOwned = _toUint128(uint256(allocation.lpTokensOwned) + liquidity);

        emit LiquidityAddedToAMM(asset, amountAsset, amountUSDFL, liquidity);

    // === REMOVE LIQUIDITY FROM AMM ===
    } else if (currentAMM > targetAMM && address(fluidAMM) != address(0)) {
        uint256 toRemove = currentAMM - targetAMM;

        // 1. Calculate LP tokens to burn (proportional to amount)
        bytes32 poolId = fluidAMM.getPoolId(asset, address(usdfToken));
        (uint256 reserveAsset, , ) = fluidAMM.getPoolReserves(poolId);

        uint256 lpTokensToBurn = (toRemove * uint256(allocation.lpTokensOwned)) / currentAMM;

        // 2. Approve AMM to burn LP tokens
        // (Assuming FluidAMM LP tokens are ERC20)
        address lpToken = fluidAMM.getLPToken(poolId);
        IERC20(lpToken).forceApprove(address(fluidAMM), lpTokensToBurn);

        // 3. Remove liquidity with 5% slippage
        uint256 minAsset = (toRemove * 95) / 100;

        (uint256 amountAsset, uint256 amountUSDFL) = fluidAMM.removeLiquidity(
            asset,
            address(usdfToken),
            lpTokensToBurn,
            minAsset,
            0,  // Accept any USDF amount
            address(this),  // Tokens to this contract
            block.timestamp + 300
        );

        // 4. Update tracking
        allocation.allocatedToAMM = _toUint128(uint256(allocation.allocatedToAMM) - amountAsset);
        allocation.lpTokensOwned = _toUint128(uint256(allocation.lpTokensOwned) - lpTokensToBurn);

        // 5. Return collateral to LiquidityCore
        IERC20(asset).forceApprove(address(liquidityCore), amountAsset);
        liquidityCore.receiveCollateralReturn(asset, amountAsset);

        // 6. Handle received USDF (return to treasury or keep for next rebalance)
        // Option A: Send to treasury
        // Option B: Keep in contract for future add liquidity operations
        // For now, keep in contract for future use

        emit LiquidityRemovedFromAMM(asset, amountAsset, amountUSDFL, lpTokensToBurn);
    }

    // Update reserve buffer
    uint256 targetVaults = (totalCollateral * config.vaultsAllocationPct) / BASIS_POINTS;
    uint256 targetStaking = (totalCollateral * config.stakingAllocationPct) / BASIS_POINTS;
    uint256 totalDeployed = targetAMM + targetVaults + targetStaking;

    allocation.reserveBuffer = _toUint128(totalCollateral - totalDeployed);
    allocation.lastRebalance = _toUint32(block.timestamp);

    emit AllocationRebalanced(asset, targetAMM, targetVaults, targetStaking);
}

// Helper function to get asset price
function _getAssetPrice(address asset) internal view returns (uint256) {
    // TODO: Integrate with PriceOracle
    // For now, return 1:1
    return 1e18;
}
```

**New Events to Add**:
```solidity
event LiquidityAddedToAMM(address indexed asset, uint256 amountAsset, uint256 amountUSDFL, uint256 liquidity);
event LiquidityRemovedFromAMM(address indexed asset, uint256 amountAsset, uint256 amountUSDFL, uint256 lpTokens);
```

---

#### **Task 1.3: Complete allocateCollateral() Function**

**Location**: Lines 285-299

**Implementation**:

```solidity
// Replace lines 285-299 with:

// === INTERACTIONS ===
// Deploy to AMM if needed
if (toAMM > 0 && address(fluidAMM) != address(0)) {
    // FIX CRIT-1: Verify LiquidityCore has the balance
    uint256 coreBalance = IERC20(asset).balanceOf(address(liquidityCore));
    require(coreBalance >= toAMM, "Insufficient LiquidityCore balance");

    // Transfer from LiquidityCore to this contract
    liquidityCore.transferCollateral(asset, address(this), toAMM);

    // Calculate optimal USDF amount
    bytes32 poolId = fluidAMM.getPoolId(asset, address(usdfToken));
    (uint256 reserveAsset, uint256 reserveUSDFL, ) = fluidAMM.getPoolReserves(poolId);

    uint256 usdfAmount;
    if (reserveAsset > 0 && reserveUSDFL > 0) {
        // Existing pool - match ratio
        usdfAmount = (toAMM * reserveUSDFL) / reserveAsset;
    } else {
        // New pool - use oracle price
        uint256 assetPrice = _getAssetPrice(asset);
        usdfAmount = (toAMM * assetPrice) / 1e18;
    }

    // Verify USDF balance
    uint256 usdfBalance = usdfToken.balanceOf(address(this));
    require(usdfBalance >= usdfAmount, "Insufficient USDF for pairing");

    // Approve AMM
    IERC20(asset).forceApprove(address(fluidAMM), toAMM);
    usdfToken.forceApprove(address(fluidAMM), usdfAmount);

    // Add liquidity with slippage protection
    (uint256 amountAsset, uint256 amountUSDFL, uint256 liquidity) = fluidAMM.addLiquidity(
        asset,
        address(usdfToken),
        toAMM,
        usdfAmount,
        (toAMM * 95) / 100,      // 5% slippage
        (usdfAmount * 95) / 100,
        address(this),
        block.timestamp + 300
    );

    // Update LP tokens tracking
    allocation.lpTokensOwned = _toUint128(uint256(allocation.lpTokensOwned) + liquidity);

    emit LiquidityAddedToAMM(asset, amountAsset, amountUSDFL, liquidity);
}
```

---

#### **Task 1.4: Add LiquidityCore Return Function**

**File**: `LiquidityCore.sol`

**Add new function**:

```solidity
/**
 * @notice Receive collateral returned from CapitalEfficiencyEngine
 * @param asset Collateral asset
 * @param amount Amount returned
 */
function receiveCollateralReturn(
    address asset,
    uint256 amount
) external override onlyAuthorized {
    require(amount > 0, "Invalid amount");

    // Transfer tokens from sender (CapitalEfficiencyEngine)
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

    // Update collateral reserve
    _assetLiquidity[asset].collateralReserve += uint128(amount);

    emit CollateralReturned(asset, amount, msg.sender);
}
```

**Add to ILiquidityCore.sol**:
```solidity
function receiveCollateralReturn(address asset, uint256 amount) external;
event CollateralReturned(address indexed asset, uint256 amount, address indexed from);
```

---

### Phase 2: Vault Integration (Week 2)

#### **Task 2.1: Create Vault Interfaces**

**New File**: `contracts/OrganisedSecured/interfaces/IVault.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVault
 * @notice Interface for yield-generating vaults (e.g., Aave, Compound)
 */
interface IVault {
    /**
     * @notice Deposit collateral into vault
     * @param asset Asset to deposit
     * @param amount Amount to deposit
     * @return shares Vault shares received
     */
    function deposit(
        address asset,
        uint256 amount
    ) external returns (uint256 shares);

    /**
     * @notice Withdraw collateral from vault
     * @param asset Asset to withdraw
     * @param shares Shares to burn
     * @return amount Amount of asset received
     */
    function withdraw(
        address asset,
        uint256 shares
    ) external returns (uint256 amount);

    /**
     * @notice Get current value of shares
     * @param asset Asset
     * @param shares Number of shares
     * @return value Current value in asset
     */
    function getShareValue(
        address asset,
        uint256 shares
    ) external view returns (uint256 value);

    /**
     * @notice Get current APY for asset
     * @param asset Asset
     * @return apy Annual percentage yield (basis points)
     */
    function getAPY(address asset) external view returns (uint256 apy);

    /**
     * @notice Check if vault is healthy
     * @return healthy True if vault is operational
     */
    function isHealthy() external view returns (bool healthy);
}
```

---

#### **Task 2.2: Create Vault Adapters**

**New File**: `contracts/OrganisedSecured/adapters/AaveVaultAdapter.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IVault.sol";

/**
 * @title AaveVaultAdapter
 * @notice Adapter for Aave V3 lending pools
 */
contract AaveVaultAdapter is IVault {
    using SafeERC20 for IERC20;

    // Aave V3 Pool interface (simplified)
    interface IAavePool {
        function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
        function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    }

    // Aave aToken interface
    interface IAToken {
        function balanceOf(address account) external view returns (uint256);
    }

    IAavePool public immutable aavePool;
    mapping(address => address) public aTokens;  // asset => aToken

    constructor(address _aavePool) {
        require(_aavePool != address(0), "Invalid Aave pool");
        aavePool = IAavePool(_aavePool);
    }

    function deposit(
        address asset,
        uint256 amount
    ) external override returns (uint256 shares) {
        // Transfer asset from sender
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve Aave
        IERC20(asset).forceApprove(address(aavePool), amount);

        // Supply to Aave
        uint256 balanceBefore = IAToken(aTokens[asset]).balanceOf(address(this));
        aavePool.supply(asset, amount, address(this), 0);
        uint256 balanceAfter = IAToken(aTokens[asset]).balanceOf(address(this));

        shares = balanceAfter - balanceBefore;
    }

    function withdraw(
        address asset,
        uint256 shares
    ) external override returns (uint256 amount) {
        // Withdraw from Aave
        amount = aavePool.withdraw(asset, shares, msg.sender);
    }

    function getShareValue(
        address asset,
        uint256 shares
    ) external view override returns (uint256 value) {
        // For Aave, aTokens are 1:1 with underlying + accrued interest
        return shares;
    }

    function getAPY(address asset) external view override returns (uint256 apy) {
        // TODO: Query Aave data provider for current supply APY
        return 500; // 5% placeholder
    }

    function isHealthy() external view override returns (bool healthy) {
        // TODO: Check Aave pool health
        return true;
    }

    // Admin function to register aTokens
    function registerAToken(address asset, address aToken) external {
        aTokens[asset] = aToken;
    }
}
```

**Similar adapters for**:
- `CompoundVaultAdapter.sol`
- `YearnVaultAdapter.sol`

---

#### **Task 2.3: Integrate Vaults in CapitalEfficiencyEngine**

**Add to CapitalEfficiencyEngine.sol**:

```solidity
// State variable (after line 172)
mapping(address => IVault) public vaults;  // asset => vault
mapping(address => uint256) public vaultShares;  // asset => shares owned

// New admin function
function setVault(address asset, address vault) external onlyValidRole(accessControl.ADMIN_ROLE()) {
    require(vault != address(0), "Invalid vault");
    vaults[asset] = IVault(vault);
}

// Implement vault withdrawal in withdrawFromStrategies()
// Replace lines 453-463 with:
if (withdrawn < amount && allocation.allocatedToVaults > 0) {
    uint256 needed = amount - withdrawn;
    uint256 fromVaults = needed.min(allocation.allocatedToVaults);

    IVault vault = vaults[asset];
    if (address(vault) != address(0)) {
        // Calculate shares to withdraw
        uint256 sharesToWithdraw = (vaultShares[asset] * fromVaults) / uint256(allocation.allocatedToVaults);

        // Withdraw from vault
        uint256 received = vault.withdraw(asset, sharesToWithdraw);

        // Update tracking
        allocation.allocatedToVaults = _toUint128(uint256(allocation.allocatedToVaults) - received);
        vaultShares[asset] -= sharesToWithdraw;
        withdrawn += received;

        emit CollateralRecalled(asset, received, "Vaults");
    }
}

// Add vault deposit function
function _depositToVault(address asset, uint256 amount) internal returns (uint256 shares) {
    IVault vault = vaults[asset];
    require(address(vault) != address(0), "No vault configured");

    // Approve vault
    IERC20(asset).forceApprove(address(vault), amount);

    // Deposit
    shares = vault.deposit(asset, amount);

    // Update tracking
    vaultShares[asset] += shares;
}
```

---

### Phase 3: Staking Integration (Week 3)

#### **Task 3.1: Create Staking Interface**

**New File**: `contracts/OrganisedSecured/interfaces/IStaking.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStaking
 * @notice Interface for liquid staking protocols (e.g., Lido, Rocket Pool)
 */
interface IStaking {
    /**
     * @notice Stake ETH/tokens
     * @param amount Amount to stake
     * @return shares Liquid staking tokens received
     */
    function stake(uint256 amount) external payable returns (uint256 shares);

    /**
     * @notice Unstake (may have unbonding period)
     * @param shares Liquid staking tokens to burn
     * @return requestId Request ID for withdrawal (if delayed)
     */
    function unstake(uint256 shares) external returns (uint256 requestId);

    /**
     * @notice Claim unstaked tokens (after unbonding)
     * @param requestId Withdrawal request ID
     * @return amount Amount received
     */
    function claimUnstaked(uint256 requestId) external returns (uint256 amount);

    /**
     * @notice Get exchange rate (staked token : underlying)
     * @return rate Exchange rate (1e18 = 1:1)
     */
    function getExchangeRate() external view returns (uint256 rate);

    /**
     * @notice Get unbonding period
     * @return period Time in seconds
     */
    function getUnbondingPeriod() external view returns (uint256 period);

    /**
     * @notice Get current staking APR
     * @return apr Annual percentage rate (basis points)
     */
    function getAPR() external view returns (uint256 apr);
}
```

---

#### **Task 3.2: Create Lido Adapter**

**New File**: `contracts/OrganisedSecured/adapters/LidoStakingAdapter.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IStaking.sol";

/**
 * @title LidoStakingAdapter
 * @notice Adapter for Lido liquid staking (ETH -> stETH)
 */
contract LidoStakingAdapter is IStaking {

    interface ILido {
        function submit(address _referral) external payable returns (uint256);
        function balanceOf(address account) external view returns (uint256);
        function transfer(address to, uint256 amount) external returns (bool);
        function transferFrom(address from, address to, uint256 amount) external returns (bool);
    }

    ILido public immutable lido;

    constructor(address _lido) {
        require(_lido != address(0), "Invalid Lido address");
        lido = ILido(_lido);
    }

    function stake(uint256 amount) external payable override returns (uint256 shares) {
        require(msg.value == amount, "Incorrect ETH amount");

        uint256 balanceBefore = lido.balanceOf(address(this));
        lido.submit{value: amount}(address(0));
        uint256 balanceAfter = lido.balanceOf(address(this));

        shares = balanceAfter - balanceBefore;
    }

    function unstake(uint256 shares) external override returns (uint256 requestId) {
        // Lido stETH is liquid - can swap directly
        // No unbonding period needed
        // Transfer stETH back to sender
        lido.transferFrom(msg.sender, address(this), shares);

        // TODO: Integrate with Lido withdrawal queue for actual ETH
        // For now, assume instant swap via Curve stETH/ETH pool

        return 0; // Instant withdrawal
    }

    function claimUnstaked(uint256 requestId) external override returns (uint256 amount) {
        // Not needed for Lido (instant via Curve)
        return 0;
    }

    function getExchangeRate() external view override returns (uint256 rate) {
        // stETH is ~1:1 with ETH (slightly higher due to rewards)
        return 1e18;
    }

    function getUnbondingPeriod() external pure override returns (uint256 period) {
        return 0; // Instant via Curve
    }

    function getAPR() external pure override returns (uint256 apr) {
        return 400; // ~4% APR for Lido staking
    }
}
```

---

### Phase 4: Testing & Deployment (Week 4)

#### **Task 4.1: Unit Tests**

**New File**: `test/OrganisedSecured/unit/CapitalEfficiencyEngine.test.ts`

```typescript
import { expect } from "chai";
import { ethers } from "hardhat";

describe("CapitalEfficiencyEngine", function () {

    describe("Rebalancing", function () {
        it("Should add liquidity to AMM when below target", async function () {
            // Setup
            // Call rebalance
            // Verify AMM liquidity increased
            // Verify LP tokens tracked
        });

        it("Should remove liquidity from AMM when above target", async function () {
            // Setup
            // Call rebalance
            // Verify AMM liquidity decreased
            // Verify LP tokens burned
        });

        it("Should not rebalance if drift below threshold", async function () {
            // Setup with 5% drift (below 10% threshold)
            // Expect revert
        });
    });

    describe("Vault Integration", function () {
        it("Should deposit to vault", async function () {
            // Test vault deposit
        });

        it("Should withdraw from vault during emergencies", async function () {
            // Test cascading withdrawal
        });
    });

    describe("Edge Cases", function () {
        it("Should handle AMM slippage", async function () {
            // Test slippage protection
        });

        it("Should revert if insufficient USDF for pairing", async function () {
            // Test USDF balance check
        });
    });
});
```

---

#### **Task 4.2: Integration Tests**

**File**: `test/OrganisedSecured/integration/V2CapitalAllocation.test.ts`

```typescript
describe("V2 Capital Allocation Integration", function () {

    it("Full flow: Deposit -> Allocate -> Rebalance -> Liquidate", async function () {
        // 1. User opens trove
        // 2. Capital allocated to AMM
        // 3. Price drops
        // 4. Liquidation triggered
        // 5. Collateral withdrawn from AMM
        // 6. User receives collateral
    });

    it("Mass liquidation with cascading withdrawal", async function () {
        // Simulate 50 troves liquidated
        // Verify cascading withdrawal works
    });
});
```

---

## 📊 Implementation Checklist

### Week 1: AMM Integration
- [ ] Add USDF token reference to CapitalEfficiencyEngine
- [ ] Complete `rebalance()` add liquidity logic
- [ ] Complete `rebalance()` remove liquidity logic
- [ ] Complete `allocateCollateral()` AMM integration
- [ ] Add `receiveCollateralReturn()` to LiquidityCore
- [ ] Add helper function `_getAssetPrice()`
- [ ] Add events: `LiquidityAddedToAMM`, `LiquidityRemovedFromAMM`
- [ ] Test compilation
- [ ] Write unit tests for rebalancing

### Week 2: Vault Integration
- [ ] Create `IVault.sol` interface
- [ ] Create `AaveVaultAdapter.sol`
- [ ] Create `CompoundVaultAdapter.sol` (optional)
- [ ] Add vault state variables to CapitalEfficiencyEngine
- [ ] Implement `setVault()` admin function
- [ ] Complete vault withdrawal in `withdrawFromStrategies()`
- [ ] Add `_depositToVault()` helper function
- [ ] Write unit tests for vault operations

### Week 3: Staking Integration
- [ ] Create `IStaking.sol` interface
- [ ] Create `LidoStakingAdapter.sol`
- [ ] Add staking state variables to CapitalEfficiencyEngine
- [ ] Implement staking withdrawal logic
- [ ] Handle unbonding period (if applicable)
- [ ] Write unit tests for staking

### Week 4: Testing & Deployment
- [ ] Complete all unit tests
- [ ] Complete integration tests
- [ ] Gas profiling
- [ ] Edge case testing
- [ ] Deployment scripts
- [ ] Deploy to testnet
- [ ] Monitor and validate

---

## 🎯 Key Design Decisions

### 1. **USDF Sourcing for AMM Pairing**

**Options**:
A. **Mint from Protocol** - Protocol can mint USDF as needed for liquidity
B. **Treasury Reserve** - Keep USDF reserve in CapitalEfficiencyEngine
C. **Single-Sided Liquidity** - Use AMM features for single-sided deposits (if supported)

**Recommendation**: Use **Treasury Reserve** approach
- Pre-fund CapitalEfficiencyEngine with USDF
- Admin function to add more USDF as needed
- Track USDF balance separately

```solidity
function fundUSDFReserve(uint256 amount) external onlyValidRole(accessControl.ADMIN_ROLE()) {
    usdfToken.safeTransferFrom(msg.sender, address(this), amount);
    emit USDFReserveFunded(amount);
}
```

---

### 2. **LP Token Tracking**

**Current**: Single `lpTokensOwned` field per asset

**Enhancement**: Track LP tokens per pool

```solidity
// Instead of:
uint128 lpTokensOwned;

// Use:
mapping(bytes32 => uint256) public lpTokensByPool;  // poolId => LP tokens

// Then in rebalance:
bytes32 poolId = fluidAMM.getPoolId(asset, address(usdfToken));
lpTokensByPool[poolId] += liquidity;
```

---

### 3. **Vault Selection Strategy**

**Priority Order** (highest APY first):
1. Check Aave APY
2. Check Compound APY
3. Allocate to highest yielding vault

**Implementation**:
```solidity
function _selectBestVault(address asset) internal view returns (IVault bestVault, uint256 bestAPY) {
    // Compare all registered vaults
    for (uint i = 0; i < registeredVaults[asset].length; i++) {
        IVault vault = registeredVaults[asset][i];
        uint256 apy = vault.getAPY(asset);
        if (apy > bestAPY) {
            bestAPY = apy;
            bestVault = vault;
        }
    }
}
```

---

### 4. **Emergency Withdrawal Priority**

**Confirmed Priority** (from AMM_LIQUIDATION_FLOW.md):
1. **Reserve** (instant, no slippage)
2. **AMM** (fast, minimal slippage)
3. **Vaults** (medium speed)
4. **Staking** (slowest, may have unbonding)

This is OPPOSITE of what the code comment says! Update accordingly.

---

## 🚀 Expected Outcomes

### Capital Efficiency
- **Before**: 0% collateral earning yield
- **After**: 70% collateral earning yield (40% AMM + 20% Vaults + 10% Staking)

### Revenue Generation
- **AMM Trading Fees**: ~0.13% per swap (protocol share)
- **Vault Yield**: ~5% APY on 20% of collateral = 1% protocol APY
- **Staking Rewards**: ~4% APR on 10% of collateral = 0.4% protocol APR
- **Total**: ~1.4% protocol APY + trading fees

### Gas Costs
- **Normal Liquidation** (reserve): ~180k gas
- **With AMM Withdrawal**: ~280k gas (+100k)
- **Rebalance Operation**: ~300-400k gas

---

## 📝 Summary

This plan provides a complete roadmap to:
1. ✅ Complete AMM integration (rebalancing + allocation)
2. ✅ Add vault support (Aave/Compound)
3. ✅ Add staking support (Lido)
4. ✅ Comprehensive testing
5. ✅ Testnet deployment

**Estimated Timeline**: 4 weeks
**Complexity**: Medium-High
**Risk**: Low (incremental approach with safety mechanisms)

**Next Step**: Begin Week 1 - Task 1.1 (Add USDF Token Reference)

---

**Status**: 📋 READY TO IMPLEMENT
**Last Updated**: October 25, 2025

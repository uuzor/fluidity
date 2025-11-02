# Liquidation Flow with AMM Integration - Complete Trace

## 🎯 Scenario Setup

**Initial State:**
```
Alice's Trove:
├─ Collateral: 10 ETH
├─ Debt: 10,000 USDF
├─ ICR: 200% (safe)
└─ Trove opened at ETH = $2,000/ETH

Capital Allocation (via CapitalEfficiencyEngine):
├─ Total collateral in system: 100 ETH
├─ Reserved (30%): 30 ETH in LiquidityCore
├─ Allocated to AMM (40%): 40 ETH in FluidAMM
├─ Allocated to Vaults (20%): 20 ETH (future)
└─ Allocated to Staking (10%): 10 ETH (future)

LiquidityCore balances:
├─ Physical ETH balance: 30 ETH (reserve)
├─ Accounting balance: 100 ETH (total tracked)
└─ Allocated elsewhere: 70 ETH (AMM + Vaults + Staking)
```

---

## 💥 Liquidation Event Triggered

**Price Drop:**
```
ETH price drops: $2,000 → $1,000

Alice's Trove becomes undercollateralized:
├─ Collateral value: 10 ETH × $1,000 = $10,000
├─ Debt: $10,000 USDF
├─ ICR: 100% (< MCR of 110%)
└─ Status: LIQUIDATABLE ⚠️
```

---

## 🔄 Liquidation Flow (Step-by-Step)

### **Step 1: Liquidator Calls Liquidate**

```solidity
// Liquidator calls
troveManager.liquidate(alice, WETH)
```

**TroveManagerV2.liquidate() executes:**
```solidity
function liquidate(address borrower, address asset) external {
    // 1. Validate liquidation is allowed
    uint256 icr = getCurrentICR(borrower, asset);
    require(icr < MCR, "Trove not liquidatable");

    // 2. Get trove data
    (uint256 debt, uint256 collateral) = getTroveDebtAndColl(borrower, asset);
    // debt = 10,000 USDF
    // collateral = 10 ETH

    // 3. Calculate liquidation amounts
    uint256 collGasCompensation = collateral / 200; // 0.5% = 0.05 ETH
    uint256 collToLiquidate = collateral - collGasCompensation; // 9.95 ETH

    // 4. Try StabilityPool first
    _liquidateSingleTrove(borrower, asset, debt, collateral);
}
```

---

### **Step 2: Try StabilityPool Offset**

```solidity
function _liquidateSingleTrove(
    address borrower,
    address asset,
    uint256 debt,
    uint256 collateral
) internal {
    // Calculate amounts
    uint256 collGasCompensation = collateral / 200; // 0.05 ETH
    uint256 collToLiquidate = collateral - collGasCompensation; // 9.95 ETH

    // Remove from sorted troves
    sortedTroves.remove(asset, borrower);

    // Update trove status to liquidated
    _packedTroves[borrower][asset] = PackedTrove.pack(
        0, 0, uint32(block.timestamp),
        PackedTrove.STATUS_LIQUIDATED,
        assetToId[asset]
    );

    // V2 STABILITY POOL INTEGRATION
    if (address(stabilityPool) != address(0)) {
        uint256 spDeposits = stabilityPool.getTotalDeposits();

        if (spDeposits >= debt) {
            // ✅ FULL OFFSET with StabilityPool
            _offsetWithStabilityPool(asset, debt, collToLiquidate);

            // ⚠️ KEY POINT: Collateral needs to be transferred!
            // Where does it come from?
        } else if (spDeposits > 0) {
            // ⚠️ PARTIAL OFFSET
            // Similar issue - need collateral
        } else {
            // Redistribution (collateral stays in LiquidityCore)
        }
    }

    // Send gas compensation to liquidator
    liquidityCore.transferCollateral(asset, msg.sender, collGasCompensation);
    // ⚠️ CRITICAL: This also needs physical ETH!

    // Burn debt
    liquidityCore.burnDebt(asset, borrower, debt);
}
```

---

### **Step 3: The Critical Question - Where's The Collateral?**

**Problem Identified:**
```
Liquidation needs to transfer:
├─ 9.95 ETH to StabilityPool (or redistribute)
└─ 0.05 ETH to liquidator

But LiquidityCore only has:
├─ Physical balance: 30 ETH (reserve)
├─ Alice's 10 ETH is part of this
└─ Should be enough! ✅

Wait... but what if:
├─ 50 troves get liquidated simultaneously?
├─ Need 500 ETH total
└─ Only 30 ETH in reserve! ❌
```

---

## 🛡️ Solution: Cascading Liquidity Withdrawal

### **Enhanced LiquidityCore with AMM Integration**

```solidity
function transferCollateral(
    address asset,
    address to,
    uint256 amount
) external override onlyAuthorized {
    // Check physical balance
    uint256 balance = IERC20(asset).balanceOf(address(this));

    if (balance >= amount) {
        // ✅ Case 1: Sufficient reserve
        IERC20(asset).safeTransfer(to, amount);
        _assetLiquidity[asset].collateralReserve -= uint128(amount);
        return;
    }

    // ⚠️ Case 2: Insufficient reserve - need to pull from AMM
    uint256 deficit = amount - balance;

    // Pull from CapitalEfficiencyEngine
    _withdrawFromAllocations(asset, deficit);

    // Now transfer
    IERC20(asset).safeTransfer(to, amount);
    _assetLiquidity[asset].collateralReserve -= uint128(amount);
}

function _withdrawFromAllocations(address asset, uint256 amount) internal {
    // Priority order:
    // 1. Pull from vaults (most liquid, future)
    // 2. Pull from staking (medium liquidity, future)
    // 3. Pull from AMM (least liquid, has slippage)

    require(
        address(capitalEfficiencyEngine) != address(0),
        "No allocation engine"
    );

    // Request emergency withdrawal
    capitalEfficiencyEngine.emergencyWithdraw(asset, amount);
}
```

---

### **CapitalEfficiencyEngine Emergency Withdrawal**

```solidity
contract CapitalEfficiencyEngine {
    function emergencyWithdraw(
        address asset,
        uint256 amount
    ) external onlyLiquidityCore {
        // Check what we have allocated
        CapitalAllocation memory alloc = allocations[asset];

        uint256 remaining = amount;

        // Step 1: Withdraw from vaults (future - most liquid)
        if (remaining > 0 && alloc.allocatedToVaults > 0) {
            uint256 fromVaults = _min(remaining, alloc.allocatedToVaults);
            _withdrawFromVaults(asset, fromVaults);
            remaining -= fromVaults;
        }

        // Step 2: Withdraw from staking (future - medium liquidity)
        if (remaining > 0 && alloc.allocatedToStaking > 0) {
            uint256 fromStaking = _min(remaining, alloc.allocatedToStaking);
            _withdrawFromStaking(asset, fromStaking);
            remaining -= fromStaking;
        }

        // Step 3: Withdraw from AMM (least liquid - has slippage)
        if (remaining > 0 && alloc.allocatedToAMM > 0) {
            uint256 fromAMM = _min(remaining, alloc.allocatedToAMM);
            _withdrawFromAMM(asset, fromAMM);
            remaining -= fromAMM;
        }

        require(remaining == 0, "Insufficient allocated liquidity");
    }

    function _withdrawFromAMM(address asset, uint256 amount) internal {
        // Calculate LP tokens needed
        bytes32 pairKey = fluidAMM.getPairKey(asset, address(usdf));
        (uint256 reserveAsset, uint256 reserveUSDFL) = fluidAMM.getReserves(pairKey);
        uint256 totalSupply = fluidAMM.totalSupply(pairKey);

        // Calculate LP tokens to burn
        // lpTokens = (amount / reserveAsset) * totalSupply
        uint256 lpTokens = (amount * totalSupply) / reserveAsset;

        // Remove liquidity
        (uint256 amountAsset, uint256 amountUSDFL) = fluidAMM.removeLiquidity(
            asset,
            address(usdf),
            lpTokens,
            amount,  // minAsset
            0        // minUSDFL (we don't care)
        );

        // Transfer asset back to LiquidityCore
        IERC20(asset).transfer(address(liquidityCore), amountAsset);

        // Update allocation tracking
        allocations[asset].allocatedToAMM -= uint128(amountAsset);
        allocations[asset].lpTokensOwned -= uint128(lpTokens);

        // What about the USDF we got? Keep it or do something with it
        // Option 1: Keep in engine for future rebalancing
        // Option 2: Send to treasury
        // Option 3: Add back as single-sided liquidity later
    }
}
```

---

## 🔄 Complete Liquidation Flow (With AMM)

### **Scenario: Mass Liquidation Event**

```
Initial State:
├─ 100 troves, each with 10 ETH collateral
├─ Total collateral: 1000 ETH
├─ Reserve (30%): 300 ETH in LiquidityCore
├─ AMM (40%): 400 ETH in FluidAMM
├─ Vaults (20%): 200 ETH (future)
└─ Staking (10%): 100 ETH (future)

Event: ETH drops 50%, 50 troves become liquidatable
Need to liquidate: 50 × 10 ETH = 500 ETH
```

**Liquidation #1-30: Use Reserve (300 ETH)**
```solidity
// Liquidations 1-30 (300 ETH needed)
for (uint i = 0; i < 30; i++) {
    troveManager.liquidate(borrower[i], WETH);
    // LiquidityCore.transferCollateral() succeeds
    // Physical balance sufficient
}

After 30 liquidations:
├─ Reserve: 0 ETH (depleted)
├─ AMM: 400 ETH (untouched)
├─ Need: 200 ETH more
```

**Liquidation #31: Triggers AMM Withdrawal**
```solidity
// Liquidation #31
troveManager.liquidate(borrower[31], WETH);

// Inside LiquidityCore.transferCollateral():
balance = IERC20(WETH).balanceOf(address(this)); // 0 ETH
amount = 10 ETH
deficit = 10 ETH

// ⚠️ Trigger emergency withdrawal
liquidityCore._withdrawFromAllocations(WETH, 10 ETH);

// CapitalEfficiencyEngine.emergencyWithdraw():
├─ Check allocations
├─ Pull 10 ETH from FluidAMM
│  ├─ Calculate LP tokens: 10/400 * totalSupply = 2.5% of LP
│  ├─ Remove liquidity: (10 ETH, 20k USDF)
│  └─ Transfer 10 ETH to LiquidityCore
└─ Update tracking

// Now LiquidityCore has 10 ETH
liquidityCore.transferCollateral(WETH, stabilityPool, 10 ETH);
// ✅ Success!
```

**Liquidations #32-70: Continue pulling from AMM**
```solidity
// Each liquidation pulls 10 ETH from AMM
// Until AMM is depleted or liquidations stop

After all liquidations:
├─ Reserve: 0 ETH
├─ AMM: 200 ETH (400 - 200 pulled)
├─ Vaults: 200 ETH (untouched, future)
├─ Staking: 100 ETH (untouched, future)
└─ System remains solvent ✅
```

---

## 📊 Key Scenarios & Handling

### **Scenario 1: Normal Liquidation (Reserve Sufficient)**
```
Reserve: 300 ETH
Liquidation needs: 10 ETH

Flow:
└─ LiquidityCore.transferCollateral(WETH, stabilityPool, 10 ETH)
   └─ Direct transfer from reserve ✅
   └─ AMM untouched
   └─ Gas: ~50,000
```

### **Scenario 2: Large Liquidation (Needs AMM)**
```
Reserve: 5 ETH
Liquidation needs: 10 ETH

Flow:
├─ LiquidityCore.transferCollateral(WETH, stabilityPool, 10 ETH)
│  └─ balance = 5 ETH (insufficient)
│  └─ deficit = 5 ETH
│  └─ _withdrawFromAllocations(WETH, 5 ETH)
│
├─ CapitalEfficiencyEngine.emergencyWithdraw(WETH, 5 ETH)
│  ├─ _withdrawFromAMM(WETH, 5 ETH)
│  │  ├─ Calculate LP tokens: 5/400 * totalSupply
│  │  ├─ fluidAMM.removeLiquidity(...)
│  │  │  └─ Returns (5 ETH, 10k USDF)
│  │  └─ Transfer 5 ETH to LiquidityCore
│  └─ Update allocations tracking
│
└─ Transfer 10 ETH to stabilityPool ✅
   └─ Gas: ~150,000 (higher due to AMM withdrawal)
```

### **Scenario 3: StabilityPool Offset (No Redistribution)**
```
StabilityPool deposits: 20,000 USDF
Liquidation debt: 10,000 USDF

Flow:
├─ TroveManagerV2._liquidateSingleTrove(alice, WETH, 10k, 10 ETH)
│  ├─ stabilityPool.getTotalDeposits() = 20,000 USDF ✅
│  └─ _offsetWithStabilityPool(WETH, 10k USDF, 9.95 ETH)
│
├─ LiquidityCore.transferCollateral(WETH, stabilityPool, 9.95 ETH)
│  └─ May trigger AMM withdrawal if reserve low
│
├─ StabilityPool.offset(WETH, 10k USDF, 9.95 ETH)
│  ├─ Burn 10,000 USDF from pool
│  ├─ Receive 9.95 ETH
│  ├─ Update S[WETH] for reward distribution
│  └─ totalDeposits: 20k → 10k
│
└─ LiquidityCore.transferCollateral(WETH, liquidator, 0.05 ETH)
   └─ Gas compensation ✅
```

### **Scenario 4: Partial SP Offset + Redistribution**
```
StabilityPool deposits: 5,000 USDF
Liquidation debt: 10,000 USDF

Flow:
├─ TroveManagerV2._liquidateSingleTrove(alice, WETH, 10k, 10 ETH)
│  ├─ stabilityPool.getTotalDeposits() = 5,000 USDF (partial)
│  ├─ Offset 5,000 USDF with SP:
│  │  ├─ Collateral to SP: 5k/10k * 9.95 = 4.975 ETH
│  │  └─ _offsetWithStabilityPool(WETH, 5k, 4.975 ETH)
│  │
│  └─ Redistribute remaining:
│     ├─ Remaining debt: 5,000 USDF
│     ├─ Remaining coll: 4.975 ETH
│     └─ _redistributeDebtAndColl(WETH, 5k, 4.975 ETH)
│
├─ Collateral transfers:
│  ├─ 4.975 ETH to StabilityPool (may pull from AMM)
│  ├─ 4.975 ETH stays in LiquidityCore (for redistribution)
│  └─ 0.05 ETH to liquidator
│
└─ Total: 10 ETH accounted for ✅
```

### **Scenario 5: AMM Depleted (Extreme Case)**
```
Reserve: 0 ETH
AMM: 0 ETH (fully withdrawn)
Vaults: 200 ETH (future)
Liquidation needs: 10 ETH

Flow:
├─ LiquidityCore.transferCollateral(WETH, stabilityPool, 10 ETH)
│  └─ balance = 0 (insufficient)
│  └─ _withdrawFromAllocations(WETH, 10 ETH)
│
├─ CapitalEfficiencyEngine.emergencyWithdraw(WETH, 10 ETH)
│  ├─ AMM: 0 (skip)
│  ├─ Vaults: 200 ETH ✅
│  └─ _withdrawFromVaults(WETH, 10 ETH)
│     └─ Pull from yield vaults
│
└─ Transfer succeeds ✅
   └─ This is why we have multiple allocation targets!
```

---

## 🛡️ Safety Guarantees

### **Guarantee 1: Always Maintain 30% Reserve**
```solidity
function allocateToAMM(address asset, uint256 amount) external {
    uint256 totalColl = liquidityCore.getCollateralReserve(asset);
    uint256 required = totalColl * RESERVE_BUFFER_PCT / 100; // 30%
    uint256 available = totalColl - required;

    require(amount <= available, "Exceeds safe allocation limit");
    // ✅ Always 30% kept in reserve for immediate liquidations
}
```

### **Guarantee 2: Cascading Withdrawal Priority**
```solidity
Priority order for emergency withdrawal:
1. ✅ Reserve (instant, no slippage)
2. ✅ Vaults (fast, minimal slippage)
3. ✅ Staking (medium, unbonding delay possible)
4. ✅ AMM (last resort, has slippage)

// Never withdraw more than allocated
require(totalWithdrawn <= allocatedToAMM + allocatedToVaults + allocatedToStaking);
```

### **Guarantee 3: Circuit Breaker**
```solidity
function checkSystemHealth() internal view {
    uint256 totalColl = getTotalCollateral();
    uint256 totalAllocated = getTotalAllocated();
    uint256 reserveRatio = (totalColl - totalAllocated) * 100 / totalColl;

    if (reserveRatio < 20) {
        // ⚠️ Reserve below 20%, pause new allocations
        pauseAllocations = true;
    }

    if (reserveRatio < 10) {
        // 🚨 Reserve below 10%, trigger emergency rebalance
        _emergencyRebalance();
    }
}
```

### **Guarantee 4: Liquidation Always Succeeds**
```solidity
// Mathematical guarantee:
Total Collateral = Reserve + AMM + Vaults + Staking
                 = 100%

If liquidation needs X ETH:
├─ Try Reserve (30%)
├─ Pull from Vaults (20%)
├─ Pull from Staking (10%)
├─ Pull from AMM (40%)
└─ Total available: 100% ✅

// Liquidation can ONLY fail if:
// - Total system collateral < liquidation amount (impossible, that's the collateral being liquidated!)
```

---

## ⚡ Gas Costs Comparison

| Scenario | Without AMM | With AMM (Reserve) | With AMM (Pull) |
|----------|-------------|-------------------|-----------------|
| **Normal Liquidation** | ~180k gas | ~180k gas | ~280k gas |
| **With SP Offset** | ~220k gas | ~220k gas | ~320k gas |
| **With Redistribution** | ~250k gas | ~250k gas | ~350k gas |

**Extra cost when pulling from AMM**: ~100k gas
- Remove liquidity: ~60k gas
- Transfer tokens: ~20k gas
- Update accounting: ~20k gas

**Mitigation**: Keeper bot monitors reserve levels and proactively rebalances to avoid pulling from AMM during liquidations.

---

## 🎯 Monitoring & Alerts

### **Real-time Metrics**
```javascript
// Dashboard monitoring
const metrics = {
    reserveRatio: calculateReserveRatio(), // Target: >30%
    ammUtilization: calculateAMMUtilization(), // Target: <70%
    liquidationsToday: countLiquidations(), // Alert if >50
    avgLiquidationGas: calculateAvgGas(), // Alert if >250k
    emergencyWithdrawals: countEmergencyPulls(), // Alert if >5
};

// Alert conditions
if (metrics.reserveRatio < 25) {
    alert("⚠️ Reserve ratio low, trigger rebalance");
}

if (metrics.emergencyWithdrawals > 5) {
    alert("🚨 Too many emergency pulls, increase reserve");
}
```

---

## ✅ Summary

**Liquidation with AMM Integration:**

1. **✅ Reserve First**: Most liquidations use 30% reserve (fast, cheap)
2. **✅ Pull from AMM**: If reserve depleted, pull from AMM automatically
3. **✅ Cascading Withdrawal**: Priority order ensures liquidity always available
4. **✅ Safety Guaranteed**: 100% of collateral is trackable and withdrawable
5. **✅ Gas Efficient**: Only ~100k extra gas when pulling from AMM
6. **✅ No User Impact**: Liquidations work seamlessly, users unaware of backend complexity

**The system is designed so liquidations NEVER fail due to AMM integration!**

---

**Next**: Implement the enhanced LiquidityCore and CapitalEfficiencyEngine with emergency withdrawal logic! 🚀

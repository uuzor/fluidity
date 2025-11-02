# Allocation Strategy Settlement Analysis & Bug Report

**Date**: October 25, 2025
**Status**: 🔍 CRITICAL BUGS IDENTIFIED
**Priority**: 🚨 FIX BEFORE TESTING

---

## 🎯 **Analysis Scope**

Analyzing the allocation strategy settlement in the context of:
1. **Lending** - User deposits to UnifiedLiquidityPool
2. **Borrowing** - User borrows from UnifiedLiquidityPool or opens CDP
3. **Capital Allocation** - CapitalEfficiencyEngine manages collateral
4. **Settlement** - Ensuring balances settle correctly across all components

---

## 🚨 **CRITICAL BUG #1: Physical vs Tracked Balance Mismatch**

### **Location**: BorrowerOperationsV2.sol:265

```solidity
// FIX HIGH-2: Ensure LiquidityCore has sufficient collateral
uint256 availableCollateral = liquidityCore.getCollateralReserve(asset);  // ❌ BUG!
if (availableCollateral < collateral) {
    // Try to recall collateral from UnifiedLiquidityPool/AMM
    uint256 shortage = collateral - availableCollateral;
    liquidityCore.borrowFromUnifiedPool(asset, shortage);  // ❌ WRONG SOLUTION!
}
```

### **The Problem**

1. `getCollateralReserve()` returns **TRACKED** balance (logical/accounting)
2. But we need **PHYSICAL** balance (actual tokens in contract)
3. The check almost NEVER triggers because tracked balance is always higher

### **Example Scenario**

```
LiquidityCore state:
├─ collateralReserve (tracked): 1000 ETH
├─ balanceOf(this) (physical): 300 ETH  ← Only 30% in reserve!
└─ Allocated: 700 ETH (to AMM/Vaults/Staking)

User tries to close trove with 10 ETH collateral:
├─ availableCollateral = liquidityCore.getCollateralReserve(WETH) = 1000 ETH
├─ collateral needed = 10 ETH
├─ Check: 1000 ETH >= 10 ETH? YES ✅
├─ Skip emergency withdrawal!
├─ Try to transfer: liquidityCore.transferCollateral(WETH, user, 10 ETH)
│
└─ transferCollateral() checks:
   ├─ balance = IERC20(WETH).balanceOf(address(this)) = 300 ETH
   ├─ amount needed = 10 ETH
   ├─ 300 >= 10? YES ✅
   └─ Transfer succeeds!

Result: Works by accident, but logic is wrong!
```

### **When It BREAKS**

```
Scenario: Reserve depleted to 5 ETH

User tries to close trove with 10 ETH collateral:
├─ availableCollateral = 1000 ETH (tracked, wrong!)
├─ Check: 1000 >= 10? YES ✅ (passes incorrectly)
├─ transferCollateral() executes:
│  ├─ balance = 5 ETH
│  ├─ amount = 10 ETH
│  ├─ Check: 5 < 10? YES ❌
│  └─ revert InsufficientCollateral!
│
└─ User transaction FAILS ❌

The emergency withdrawal was never triggered because we checked the wrong balance!
```

### **The Fix**

```solidity
// ✅ CORRECT: Check physical balance
uint256 physicalBalance = IERC20(asset).balanceOf(address(liquidityCore));
if (physicalBalance < collateral) {
    // Recall from CapitalEfficiencyEngine (not UnifiedLiquidityPool!)
    uint256 shortage = collateral - physicalBalance;

    // ✅ Use CapitalEfficiencyEngine.withdrawFromStrategies()
    capitalEfficiencyEngine.withdrawFromStrategies(
        asset,
        shortage,
        address(liquidityCore)
    );
}
```

---

## 🚨 **CRITICAL BUG #2: Wrong Emergency Liquidity Source**

### **Location**: BorrowerOperationsV2.sol:269

```solidity
liquidityCore.borrowFromUnifiedPool(asset, shortage);  // ❌ WRONG!
```

### **The Problem**

1. UnifiedLiquidityPool is a **SEPARATE lending market**
2. It doesn't have the CDP collateral that's allocated to AMM!
3. UnifiedLiquidityPool users deposit their own assets
4. Those assets are NOT the same as CDP collateral allocated by CapitalEfficiencyEngine

### **Architecture Clarification**

```
CDP Collateral Flow:
User → LiquidityCore → CapitalEfficiencyEngine → AMM/Vaults/Staking
(This is CDP user's collateral backing their USDF debt)

UnifiedLiquidityPool Flow:
Lender → UnifiedLiquidityPool → Borrower
(This is separate lending market, different users, different assets)
```

### **Why borrowFromUnifiedPool() Won't Help**

```
Scenario: CDP user deposited 10 ETH, allocated to AMM

UnifiedLiquidityPool state:
├─ Users deposited 100 WBTC (different users!)
├─ Users borrowed 50 WBTC
└─ Available liquidity: 50 WBTC

CDP user tries to close trove:
├─ Need: 10 ETH
├─ borrowFromUnifiedPool(WETH, 10 ETH)
│  ├─ UnifiedLiquidityPool checks: do we have 10 WETH?
│  ├─ Available WETH in pool: 0 ETH ❌ (users deposited WBTC, not WETH!)
│  └─ revert InsufficientLiquidity!
│
└─ Transaction fails ❌

The 10 ETH is in the FluidAMM, not in UnifiedLiquidityPool!
```

### **The Correct Solution**

The collateral is in **CapitalEfficiencyEngine** strategies (AMM/Vaults/Staking), so we must recall from there:

```solidity
// ✅ CORRECT
capitalEfficiencyEngine.withdrawFromStrategies(
    asset,
    shortage,
    address(liquidityCore)
);
```

This will:
1. Pull from AMM first (most liquid)
2. Pull from Vaults if needed (medium liquidity)
3. Pull from Staking if needed (least liquid)
4. Transfer collateral back to LiquidityCore
5. Now LiquidityCore has physical balance to transfer to user

---

## 🚨 **CRITICAL BUG #3: Missing CapitalEfficiencyEngine Reference**

### **Location**: BorrowerOperationsV2.sol (entire contract)

```solidity
// ❌ NO REFERENCE TO CapitalEfficiencyEngine!
// How can we call withdrawFromStrategies() if we don't have the reference?
```

### **The Problem**

BorrowerOperationsV2 needs to recall collateral from strategies, but it doesn't have a reference to CapitalEfficiencyEngine!

### **The Fix**

```solidity
// Add to BorrowerOperationsV2.sol

// ============ State Variables ============
ICapitalEfficiencyEngine public capitalEfficiencyEngine;

// ============ Admin Functions ============
function setCapitalEfficiencyEngine(address _engine)
    external
    onlyValidRole(accessControl.ADMIN_ROLE())
{
    require(_engine != address(0), "BO: Invalid engine");
    require(address(capitalEfficiencyEngine) == address(0), "BO: Engine already set");
    capitalEfficiencyEngine = ICapitalEfficiencyEngine(_engine);
}
```

---

## 🐛 **BUG #4: adjustTrove() Has Same Issue**

### **Location**: BorrowerOperationsV2.sol:adjustTrove() (lines 303-349)

```solidity
function adjustTrove(...) external payable override nonReentrant whenNotPaused {
    // ... lots of logic ...

    // === Collateral changes ===
    if (collateralChange > 0) {
        if (isCollateralIncrease) {
            IERC20(vars.asset).safeTransferFrom(msg.sender, address(liquidityCore), collateralChange);
            liquidityCore.depositCollateral(vars.asset, msg.sender, collateralChange);
        } else {
            // ❌ WITHDRAWING COLLATERAL - Same bug as closeTrove()!
            liquidityCore.withdrawCollateral(vars.asset, msg.sender, collateralChange);
            liquidityCore.transferCollateral(vars.asset, msg.sender, collateralChange);
        }
    }
}
```

### **The Problem**

When user withdraws collateral via `adjustTrove()`:
1. No check if LiquidityCore has physical balance
2. Will fail if balance is in AMM/Vaults/Staking

### **The Fix**

```solidity
if (collateralChange > 0) {
    if (isCollateralIncrease) {
        IERC20(vars.asset).safeTransferFrom(msg.sender, address(liquidityCore), collateralChange);
        liquidityCore.depositCollateral(vars.asset, msg.sender, collateralChange);
    } else {
        // ✅ FIX: Check physical balance before withdrawal
        uint256 physicalBalance = IERC20(vars.asset).balanceOf(address(liquidityCore));
        if (physicalBalance < collateralChange) {
            uint256 shortage = collateralChange - physicalBalance;
            capitalEfficiencyEngine.withdrawFromStrategies(
                vars.asset,
                shortage,
                address(liquidityCore)
            );
        }

        liquidityCore.withdrawCollateral(vars.asset, msg.sender, collateralChange);
        liquidityCore.transferCollateral(vars.asset, msg.sender, collateralChange);
    }
}
```

---

## 🐛 **BUG #5: Liquidation Missing Physical Balance Check**

### **Location**: TroveManagerV2.sol:373

```solidity
// Send gas compensation to liquidator
liquidityCore.transferCollateral(asset, msg.sender, collGasCompensation);
```

And line 393:
```solidity
// Transfer collateral to Stability Pool
liquidityCore.transferCollateral(asset, address(stabilityPool), collToAdd);
```

### **The Problem**

During liquidation, TroveManager calls `transferCollateral()` multiple times:
1. Gas compensation to liquidator
2. Collateral to StabilityPool

If physical balance is low, these will fail!

### **Current Mitigation**

`transferCollateral()` already checks balance (line 200 in LiquidityCore):
```solidity
uint256 balance = IERC20(asset).balanceOf(address(this));
if (balance < amount) {
    revert InsufficientCollateral(asset, amount, balance);
}
```

So it will **revert** with a clear error instead of silently failing.

### **But This is Not Ideal!**

The liquidation transaction fails completely, which could cause:
1. Liquidator loses gas
2. Undercollateralized trove remains open
3. System risk increases

### **The Fix**

TroveManager needs to **proactively recall** collateral from strategies:

```solidity
function _liquidateSingleTrove(...) internal {
    // Calculate liquidation amounts
    uint256 collGasCompensation = collateral / PERCENT_DIVISOR;
    uint256 collToLiquidate = collateral - collGasCompensation;

    // ✅ FIX: Ensure LiquidityCore has physical balance
    uint256 totalNeeded = collGasCompensation + collToLiquidate;
    uint256 physicalBalance = IERC20(asset).balanceOf(address(liquidityCore));

    if (physicalBalance < totalNeeded) {
        uint256 shortage = totalNeeded - physicalBalance;

        // Recall from CapitalEfficiencyEngine
        capitalEfficiencyEngine.withdrawFromStrategies(
            asset,
            shortage,
            address(liquidityCore)
        );
    }

    // Now proceed with liquidation...
    // Transfer collateral to Stability Pool
    liquidityCore.transferCollateral(asset, address(stabilityPool), collToAdd);

    // Send gas compensation to liquidator
    liquidityCore.transferCollateral(asset, msg.sender, collGasCompensation);
}
```

**But wait!** TroveManager also doesn't have CapitalEfficiencyEngine reference!

```solidity
// Add to TroveManagerV2.sol

ICapitalEfficiencyEngine public capitalEfficiencyEngine;

function setCapitalEfficiencyEngine(address _engine)
    external
    onlyValidRole(accessControl.ADMIN_ROLE())
{
    require(_engine != address(0), "TM: Invalid engine");
    require(address(capitalEfficiencyEngine) == address(0), "TM: Engine already set");
    capitalEfficiencyEngine = ICapitalEfficiencyEngine(_engine);
}
```

---

## 📊 **Allocation Settlement Flow Analysis**

### **Scenario 1: User Opens Trove**

```
1. User calls openTrove(WETH, 10 ETH, 10000 USDF)
   │
2. Transfer 10 ETH to LiquidityCore ✅
   │
3. LiquidityCore.depositCollateral(WETH, user, 10 ETH)
   ├─ collateralReserve: 990 → 1000 ETH (tracked) ✅
   └─ Physical balance: 290 → 300 ETH ✅
   │
4. ❌ MISSING: CapitalEfficiencyEngine rebalancing!
   │
   Expected flow:
   ├─ CapitalEfficiencyEngine detects 10 ETH new collateral
   ├─ Calculate allocation: 40% to AMM = 4 ETH
   ├─ Transfer 4 ETH from LiquidityCore to AMM
   ├─ Update tracking:
   │  ├─ LiquidityCore physical: 300 → 296 ETH
   │  ├─ CapitalEfficiencyEngine.allocatedToAMM: +4 ETH
   │  └─ FluidAMM reserves: +4 ETH
   │
   Actual flow:
   └─ ❌ NOTHING HAPPENS! CapitalEfficiencyEngine not called!
```

**Problem**: `allocateCollateral()` is NOT automatically triggered!

**Solution**: Either:
1. Manual: Admin calls `capitalEfficiencyEngine.allocateCollateral()` periodically
2. Keeper bot: Monitors and calls rebalancing
3. Automatic: Hook in `depositCollateral()` to trigger allocation

---

### **Scenario 2: User Closes Trove**

```
Initial state:
├─ LiquidityCore tracked: 1000 ETH
├─ LiquidityCore physical: 296 ETH (30% of 1000 - previous allocation)
├─ CapitalEfficiencyEngine AMM: 400 ETH
├─ CapitalEfficiencyEngine Vaults: 200 ETH
└─ CapitalEfficiencyEngine Staking: 100 ETH

User calls closeTrove(WETH):
├─ Need to return: 10 ETH collateral
│
├─ ❌ BUG #1: Check tracked balance instead of physical
│  ├─ availableCollateral = 1000 ETH (tracked)
│  ├─ 1000 >= 10? YES
│  └─ Skip emergency withdrawal ❌
│
├─ Try transferCollateral(WETH, user, 10 ETH)
│  ├─ balance = 296 ETH (physical)
│  ├─ 296 >= 10? YES ✅
│  └─ Transfer succeeds ✅ (lucky!)
│
└─ Result: Works, but for wrong reason!
```

**What should happen**:

```
User calls closeTrove(WETH):
├─ Need: 10 ETH
│
├─ ✅ FIX: Check physical balance
│  ├─ physicalBalance = 296 ETH
│  ├─ 296 >= 10? YES ✅
│  └─ No recall needed, transfer directly
│
└─ Transfer succeeds ✅ (correct reason!)
```

---

### **Scenario 3: Mass Liquidation (Critical)**

```
Initial state:
├─ LiquidityCore tracked: 1000 ETH
├─ LiquidityCore physical: 300 ETH (30% reserve)
├─ Allocated to AMM: 400 ETH
├─ Allocated to Vaults: 200 ETH
└─ Allocated to Staking: 100 ETH

Event: ETH price drops 50%, 50 troves liquidatable
Need to liquidate: 50 × 10 ETH = 500 ETH

Liquidation #1-30: (need 300 ETH)
├─ Physical balance: 300 ETH ✅
├─ Transfer 10 ETH × 30 times ✅
└─ Physical balance: 300 → 0 ETH

Liquidation #31: (need 10 ETH)
├─ Physical balance: 0 ETH ❌
├─ Try liquidityCore.transferCollateral(WETH, stabilityPool, 10 ETH)
│  ├─ balance = 0 ETH
│  ├─ 0 < 10? YES ❌
│  └─ revert InsufficientCollateral! ❌
│
└─ ❌ LIQUIDATION FAILS!

System breaks:
├─ 20 troves remain undercollateralized
├─ Liquidators stop trying (losing gas)
├─ System becomes insolvent
└─ 🚨 PROTOCOL FAILURE
```

**What SHOULD happen with fixes**:

```
Liquidation #31: (need 10 ETH)
├─ TroveManager._liquidateSingleTrove()
│  ├─ totalNeeded = 10 ETH (gas compensation + liquidation)
│  ├─ physicalBalance = 0 ETH
│  ├─ shortage = 10 ETH
│  │
│  ├─ ✅ capitalEfficiencyEngine.withdrawFromStrategies(WETH, 10 ETH, liquidityCore)
│  │  ├─ Try AMM first (400 ETH available)
│  │  ├─ fluidAMM.emergencyWithdrawLiquidity(WETH, 10 ETH, capitalEfficiencyEngine)
│  │  ├─ Transfer 10 ETH to LiquidityCore
│  │  └─ allocatedToAMM: 400 → 390 ETH
│  │
│  └─ LiquidityCore physical balance: 0 → 10 ETH ✅
│
├─ transferCollateral succeeds ✅
└─ Liquidation #31 completes ✅

Liquidations #32-70: Continue pulling from AMM/Vaults/Staking
└─ All liquidations succeed ✅ System remains healthy ✅
```

---

## 🎯 **Edge Cases to Test**

### **Edge Case 1: Exact Reserve Match**
```
Physical balance: 300 ETH
User withdraws: 300 ETH
Expected: Transfer succeeds, balance = 0
```

### **Edge Case 2: Just Below Reserve**
```
Physical balance: 299 ETH
User withdraws: 300 ETH
Expected: Recall 1 ETH from AMM, then transfer
```

### **Edge Case 3: AMM Has Insufficient Liquidity**
```
Physical balance: 0 ETH
AMM: 5 ETH
Vaults: 200 ETH
User withdraws: 10 ETH
Expected:
├─ Pull 5 ETH from AMM
├─ Pull 5 ETH from Vaults
└─ Transfer 10 ETH
```

### **Edge Case 4: Total Insufficient Liquidity**
```
Physical balance: 0 ETH
AMM: 0 ETH
Vaults: 0 ETH
Staking: 0 ETH
User withdraws: 10 ETH
Expected: Revert with clear error (impossible, shouldn't happen)
```

### **Edge Case 5: Partial Liquidation During Recall**
```
Physical balance: 0 ETH
AMM: 100 ETH
Liquidate 50 troves simultaneously (need 500 ETH)
Expected:
├─ Pull 100 ETH from AMM
├─ Pull 200 ETH from Vaults
├─ Pull 100 ETH from Staking
├─ Total: 400 ETH
└─ Liquidate first 40 troves, remaining 10 fail gracefully
```

### **Edge Case 6: Rebalance During User Operation**
```
T1: User calls closeTrove() - needs 10 ETH
T2: Keeper calls rebalance() - moving collateral to AMM
Race condition: Which transaction gets priority?
Expected: Proper nonce/sequence handling, no double-spend
```

### **Edge Case 7: Flash Crash Scenario**
```
Price drops 90% instantly
All troves liquidatable simultaneously
Network congested (high gas)
Expected:
├─ Circuit breakers trigger
├─ Pause new operations
├─ Allow emergency withdrawals only
└─ Systematic liquidation queue
```

### **Edge Case 8: AMM Slippage During Recall**
```
Need to recall 100 ETH from AMM
AMM has 100 ETH in reserves
But removing liquidity causes slippage
Actual received: 95 ETH
Expected:
├─ Detect slippage
├─ Pull additional from Vaults (5 ETH)
└─ Ensure user gets full amount
```

---

## ✅ **Summary of Bugs Found**

| Bug # | Severity | Location | Description | Impact |
|-------|----------|----------|-------------|--------|
| **#1** | 🚨 CRITICAL | BorrowerOperationsV2:265 | Checks tracked balance instead of physical | Prevents emergency recall when needed |
| **#2** | 🚨 CRITICAL | BorrowerOperationsV2:269 | Uses wrong liquidity source (UnifiedPool) | Recall fails, user can't withdraw |
| **#3** | 🚨 CRITICAL | BorrowerOperationsV2 (all) | Missing CapitalEfficiencyEngine reference | Can't recall from strategies |
| **#4** | 🚨 HIGH | BorrowerOperationsV2:adjustTrove() | Same as Bug #1 & #2 in adjustTrove | User can't withdraw collateral |
| **#5** | 🚨 HIGH | TroveManagerV2:_liquidateSingleTrove | Missing physical balance check | Liquidations fail, system insolvency risk |

---

## 🔧 **Required Fixes (Priority Order)**

### **Fix 1: Add CapitalEfficiencyEngine Reference (Both Contracts)**

**BorrowerOperationsV2.sol**:
```solidity
ICapitalEfficiencyEngine public capitalEfficiencyEngine;

function setCapitalEfficiencyEngine(address _engine)
    external
    onlyValidRole(accessControl.ADMIN_ROLE())
{
    require(_engine != address(0), "BO: Invalid engine");
    require(address(capitalEfficiencyEngine) == address(0), "BO: Engine already set");
    capitalEfficiencyEngine = ICapitalEfficiencyEngine(_engine);
}
```

**TroveManagerV2.sol**:
```solidity
ICapitalEfficiencyEngine public capitalEfficiencyEngine;

function setCapitalEfficiencyEngine(address _engine)
    external
    onlyValidRole(accessControl.ADMIN_ROLE())
{
    require(_engine != address(0), "TM: Invalid engine");
    require(address(capitalEfficiencyEngine) == address(0), "TM: Engine already set");
    capitalEfficiencyEngine = ICapitalEfficiencyEngine(_engine);
}
```

### **Fix 2: Fix closeTrove() Physical Balance Check**

### **Fix 3: Fix adjustTrove() Physical Balance Check**

### **Fix 4: Fix _liquidateSingleTrove() Physical Balance Check**

All fixes follow the same pattern - check physical balance, recall from strategies if needed.

---

## 🧪 **Next Steps**

1. ✅ Analyze allocation settlement → **COMPLETE**
2. ✅ Identify bugs → **COMPLETE (5 critical bugs found)**
3. ⏳ Fix bugs → **NEXT**
4. ⏳ Write comprehensive tests → **AFTER FIXES**

---

**Status**: 🚨 **CRITICAL BUGS IDENTIFIED - MUST FIX BEFORE TESTING**
**Last Updated**: October 25, 2025

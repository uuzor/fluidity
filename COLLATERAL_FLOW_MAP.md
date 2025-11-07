# Collateral Flow Map - BorrowerOperationsV2

## Overview
This document tracks the complete lifecycle of collateral from the moment a user opens a trove (CDP) until they close it.

---

## 1. OPENING A TROVE - `openTrove()`

### Flow Diagram
```
User with WETH/WBTC collateral
        ↓
    openTrove(asset, maxFee, collateralAmount, usdfAmount, hints)
        ↓
    [VALIDATION PHASE]
    ├─ Asset is valid?
    ├─ Amounts > 0?
    ├─ Trove doesn't already exist?
    └─ USDF amount >= MIN_NET_DEBT (2000)?
        ↓
    [FEE CALCULATION PHASE]
    ├─ Get asset price from PriceOracle
    ├─ Calculate borrowing fee = usdfAmount * feeRate
    └─ Validate fee <= maxFeePercentage
        ↓
    [TOTAL DEBT CALCULATION]
    Total Debt = usdfAmount + borrowingFee + GAS_COMPENSATION(200)
        ↓
    [ICR VALIDATION - COLLATERAL RATIO CHECK]
    ICR = (collateralAmount * price) / totalDebt
    Require: ICR >= MCR (110%)
        ↓
    [COLLATERAL TRANSFER - USER → LIQUIDITY CORE]
    IERC20(asset).safeTransferFrom(user, liquidityCore, collateralAmount)
        ↓
    [LIQUIDITY CORE ACCOUNTING]
    liquidityCore.depositCollateral(asset, user, collateralAmount)
    └─ Tracks: userDeposits[user][asset] += collateralAmount
        ↓
    [USDF DEBT REGISTRATION]
    liquidityCore.mintDebt(asset, user, totalDebt)
    └─ Tracks: userDebt[user][asset] += totalDebt
        ↓
    [TROVE MANAGER STATE UPDATE]
    troveManager.updateTrove(user, asset, totalDebt, collateralAmount, isIncrease=true)
    └─ Creates trove in TroveManager (single source of truth)
        ↓
    [LOCAL TRACKING FOR GAS OPTIMIZATION]
    _isTroveActive[user][asset] = true
    _userTroveAssets[user].push(asset)
        ↓
    [SORTED LIST INSERTION]
    Calculate nominalICR = (collateral * NICR_PRECISION) / debt
    sortedTroves.insert(asset, user, nominalICR, upperHint, lowerHint)
    └─ Used for efficient liquidation scanning
        ↓
    [USDF MINTING - GENERATE STABLECOIN]
    usdfToken.mint(user, usdfAmount)
    └─ User receives the borrowed USDF amount
        ↓
    [FEE DISTRIBUTION]
    if (borrowingFee > 0):
        usdfToken.mint(liquidityCore, borrowingFee)
        emit BorrowingFeePaid(user, asset, fee)

    if (GAS_COMPENSATION > 0):
        usdfToken.mint(liquidityCore, GAS_COMPENSATION)
        ↓
    ✅ TROVE OPENED - Collateral locked in LiquidityCore
```

### State After Opening
```
User's Holdings:
├─ WETH/WBTC: -collateralAmount (transferred to LiquidityCore)
└─ USDF: +usdfAmount (minted from protocol)

LiquidityCore's Holdings:
├─ Physical collateral: +collateralAmount (WETH/WBTC tokens)
├─ User deposits tracked: userDeposits[user][asset] = collateralAmount
└─ User debt tracked: userDebt[user][asset] = totalDebt

Trove Status:
├─ TroveManager state: (debt=totalDebt, collateral=collateralAmount, status=ACTIVE)
├─ SortedTroves position: Ranked by nominalICR
└─ Local tracking: _isTroveActive[user][asset] = true
```

---

## 2. COLLATERAL ALLOCATION - Physical vs Tracked

### Key Concept: Dual Balance System
```
Total Collateral Tracked in System: 100% (tracked in userDeposits)
Physical Collateral in LiquidityCore: ~30% (actually held)

Remaining 70% allocated to:
├─ FluidAMM (DEX): 40% ──→ Provides swap liquidity
├─ Yield Vaults: 20% ──→ Generates yield through strategies
├─ Liquid Staking: 10% ──→ Earns staking rewards
└─ Reserve: 0% (kept as physical safety buffer)
```

### Location of Collateral
```
CLOSED TROVE (User's collateral):
    └─ LiquidityCore contract
        ├─ Physical balance (IERC20 balanceOf)
        ├─ Or in yield strategies via CapitalEfficiencyEngine
        │   ├─ FluidAMM (swappable assets)
        │   ├─ VaultStrategies (Aave/Lido)
        │   └─ StakingPool (staked WETH/WBTC)
        └─ Tracked in state mappings

Tracked in:
    ├─ LiquidityCore.userDeposits[user][asset]
    └─ TroveManager.troves[user][asset].coll
```

---

## 3. CLOSING A TROVE - `closeTrove()`

### Flow Diagram
```
User with active trove (WETH/WBTC locked)
        ↓
    closeTrove(asset)
        ↓
    [VALIDATION PHASE]
    ├─ Asset is valid?
    └─ Trove is active?
        ↓
    [READ TROVE STATE FROM TROVE MANAGER]
    (debt, collateral) = troveManager.getTroveDebtAndColl(user, asset)
    └─ Reads from single source of truth
        ↓
    [CHECK PHYSICAL BALANCE]
    physicalBalance = IERC20(asset).balanceOf(liquidityCore)

    if (physicalBalance < collateral) {
        [RECALL FROM YIELD STRATEGIES - CASCADING WITHDRAWAL]
        shortage = collateral - physicalBalance

        Withdrawal Priority Order:
        1. FluidAMM liquidity → withdraw(collateral) → transfer to LiquidityCore
        2. Yield Vaults → emergencyWithdraw() → transfer to LiquidityCore
        3. Staking Pool → unstake() → transfer to LiquidityCore

        Triggered via: capitalEfficiencyEngine.withdrawFromStrategies(asset, shortage, liquidityCore)
    }
        ↓
    [BURN USDF DEBT FROM USER]
    usdfToken.burnFrom(user, debt)
    └─ User must have USDF in wallet to repay debt
        ↓
    [UPDATE LIQUIDITY CORE DEBT]
    liquidityCore.burnDebt(asset, user, debt)
    └─ Removes debt tracking: userDebt[user][asset] -= debt
        ↓
    [UPDATE LIQUIDITY CORE COLLATERAL]
    liquidityCore.withdrawCollateral(asset, user, collateral)
    └─ Removes collateral tracking: userDeposits[user][asset] -= collateral
        ↓
    [TRANSFER COLLATERAL BACK TO USER]
    liquidityCore.transferCollateral(asset, user, collateral)
    └─ IERC20(asset).transfer(user, collateral)
        ↓
    [TROVE MANAGER STATE CLEANUP]
    troveManager.closeTrove(user, asset)
    └─ This triggers:
        ├─ Remove stake
        ├─ Mark trove status as CLOSED
        ├─ Clear risk snapshots
        ├─ Remove from SortedTroves
        └─ Emit TroveUpdated event
        ↓
    [LOCAL TRACKING CLEANUP]
    _isTroveActive[user][asset] = false
    _removeAssetFromUserList(user, asset)
    └─ Removes from gas-efficient lookup tables
        ↓
    ✅ TROVE CLOSED - Collateral returned to user
```

### State After Closing
```
User's Holdings:
├─ WETH/WBTC: +collateralAmount (returned from LiquidityCore)
└─ USDF: -debt (burned from wallet)

LiquidityCore's Holdings:
├─ Physical collateral: -collateralAmount (transferred out to user)
├─ User deposits: userDeposits[user][asset] = 0
└─ User debt: userDebt[user][asset] = 0

Trove Status:
├─ TroveManager state: (status=CLOSED, removed from active)
├─ SortedTroves: Entry removed (no longer ranked)
└─ Local tracking: _isTroveActive[user][asset] = false
```

---

## 4. COLLATERAL WITHDRAWAL FLOW DURING CLOSETROVE

### Scenario: Insufficient Physical Balance

If user deposits 100 WETH, but only 30 WETH physically in LiquidityCore:
- 40 WETH in FluidAMM (as swap liquidity)
- 20 WETH in Yield Vaults (earning interest)
- 10 WETH in Staking (earning rewards)

### Cascading Withdrawal Process

```
User closeTrove with 100 WETH collateral
        ↓
Physical check: 30 WETH in LiquidityCore < 100 WETH needed
        ↓
Shortage detected: 100 - 30 = 70 WETH to recall
        ↓
[STAGE 1: WITHDRAW FROM FLUIDDEX]
Call capitalEfficiencyEngine.withdrawFromStrategies(asset, 70 WETH, liquidityCore)
    └─ FluidAMM.emergencyWithdraw(70 WETH)
       ├─ Removes 40 WETH from AMM pool
       ├─ Burns corresponding LP shares
       └─ Transfers 40 WETH to LiquidityCore

        After: Need 30 more WETH
        ↓
[STAGE 2: WITHDRAW FROM YIELD VAULTS]
    └─ VaultStrategies.withdraw(30 WETH)
       ├─ Unstakes from Aave/Lido
       ├─ Burns yield pool shares
       └─ Transfers 30 WETH to LiquidityCore

        After: Need 0 more WETH (complete)
        ↓
[STAGE 3: (SKIPPED - ALREADY COMPLETE)]
    └─ StakingPool.unstake() - Not needed
        ↓
[FINAL STATE]
LiquidityCore now has 100 WETH available
    ├─ 30 WETH original physical balance
    ├─ 40 WETH recalled from FluidAMM
    ├─ 30 WETH recalled from Vaults
    └─ Total: 100 WETH ✅
        ↓
Transfer 100 WETH to user
```

---

## 5. ADJUSTING A TROVE - `adjustTrove()`

### Flow for Collateral Increase

```
User with 50 WETH, wants to add 25 WETH more
        ↓
    adjustTrove(asset, fee, 25, 0, isIncrease=true, isDecrease=false)
        ↓
    [GET CURRENT STATE]
    (currentDebt, currentCollateral) = troveManager.getTroveDebtAndColl(user, asset)
    └─ currentCollateral = 50 WETH
        ↓
    [CALCULATE NEW COLLATERAL]
    newCollateral = 50 + 25 = 75 WETH
        ↓
    [VALIDATE NEW ICR]
    newICR = (75 * price) / debt
    Require: newICR >= MCR
        ↓
    [TRANSFER ADDITIONAL COLLATERAL]
    IERC20(asset).safeTransferFrom(user, liquidityCore, 25 WETH)
        ↓
    [UPDATE LIQUIDITY CORE]
    liquidityCore.depositCollateral(asset, user, 25 WETH)
    └─ userDeposits[user][asset] += 25
        ↓
    [UPDATE TROVE MANAGER]
    troveManager.updateTrove(user, asset, debt, 75 WETH, isIncrease=true)
        ↓
    [REINSERT IN SORTED LIST]
    newNominalICR = (75 * NICR_PRECISION) / debt
    sortedTroves.reInsert(asset, user, newNominalICR)
    └─ Position updated based on new ratio
        ↓
    ✅ COLLATERAL INCREASED - 75 WETH total locked
```

### Flow for Collateral Decrease

```
User with 75 WETH, wants to withdraw 25 WETH
        ↓
    adjustTrove(asset, fee, 25, 0, isIncrease=false, isDecrease=true)
        ↓
    [CHECK PHYSICAL BALANCE]
    physicalBalance = IERC20(asset).balanceOf(liquidityCore)

    if (physicalBalance < 25) {
        [RECALL FROM STRATEGIES]
        shortage = 25 - physicalBalance
        capitalEfficiencyEngine.withdrawFromStrategies(asset, shortage, liquidityCore)
    }
        ↓
    [UPDATE LIQUIDITY CORE]
    liquidityCore.withdrawCollateral(asset, user, 25 WETH)
    └─ userDeposits[user][asset] -= 25
        ↓
    [TRANSFER TO USER]
    liquidityCore.transferCollateral(asset, user, 25 WETH)
        ↓
    [VALIDATE NEW ICR]
    newCollateral = 75 - 25 = 50 WETH
    newICR = (50 * price) / debt
    Require: newICR >= MCR
        ↓
    [UPDATE TROVE MANAGER]
    troveManager.updateTrove(user, asset, debt, 50 WETH, isIncrease=false)
        ↓
    [REINSERT IN SORTED LIST]
    newNominalICR = (50 * NICR_PRECISION) / debt
    sortedTroves.reInsert(asset, user, newNominalICR)
        ↓
    ✅ COLLATERAL DECREASED - 50 WETH locked, 25 returned
```

---

## 6. KEY DATA STRUCTURES

### BorrowerOperationsV2 Tracking
```solidity
// Is user's trove active in this asset?
mapping(address user => mapping(address asset => bool)) _isTroveActive

// Which assets does user have troves in? (for enumeration)
mapping(address user => address[]) _userTroveAssets

// Quick lookup to avoid searching array
mapping(address user => mapping(address asset => uint256 index)) _userAssetIndex
```

### TroveManager Tracking (SINGLE SOURCE OF TRUTH)
```solidity
// Complete trove data per user per asset
mapping(address user => mapping(address asset => Trove)) troves
// Contains: { debt, collateral, status, stake, coll_shares, etc. }

// Ranking for efficient liquidation
SortedTroves: red-black tree sorted by nominalICR
```

### LiquidityCore Tracking
```solidity
// Physical collateral held
IERC20(asset).balanceOf(address(liquidityCore))

// User's allocated collateral amount (tracked, may not be physical)
mapping(address user => mapping(address asset => uint256)) userDeposits

// User's tracked debt amount
mapping(address user => mapping(address asset => uint256)) userDebt

// Pending rewards from liquidations
mapping(address user => mapping(address asset => uint256)) pendingRewards
```

---

## 7. CRITICAL INVARIANTS

### Must Always Be True
```
1. [COLLATERAL CONSERVATION]
   Sum of all userDeposits[asset] <= LiquidityCore physical balance + Allocated to strategies

2. [DEBT ACCOUNTING]
   All USDF minted = sum of all userDebt + fees + gas compensation

3. [SORTED LIST CONSISTENCY]
   SortedTroves entries = number of active troves in TroveManager

4. [LOCAL VS TROVE MANAGER]
   _isTroveActive[user][asset] == (TroveManager.troves[user][asset].status == ACTIVE)

5. [PRICE CONSISTENCY]
   All price checks use same price oracle within a transaction (via transient caching)
```

### What Could Break These
```
❌ Missing recall from strategies → Not enough physical balance for withdrawal
❌ Trove state not synced → Local tracking differs from TroveManager
❌ Price oracle failure → Invalid ICR calculations
❌ Missing cascading withdrawal → Collateral stuck in non-physical locations
```

---

## 8. GAS OPTIMIZATIONS USED

```
1. TransientStorage (EIP-1153)
   - Caches price in PRICE_CACHE_SLOT
   - Saves ~2,100 gas when price reused in same tx
   - Reentrancy guard instead of storage (saves ~19,800 gas)

2. Sorted List with Hints
   - Provides hints to skip O(n) traversal
   - Saves ~25,000 gas on insert/reinsert operations

3. Nominal ICR (without price)
   - Avoids price lookup for sorting
   - nominalICR = (collateral * NICR_PRECISION) / debt
   - Only uses price when calculating actual ICR (individual collateralization ratio)

4. Local _isTroveActive Mapping
   - Gas-efficient check vs reading from TroveManager
   - ~2,100 gas saved vs struct read

5. GasOptimizedMath Library
   - Safe mulDiv without overflow checks when not needed
   - ~600 gas per calculation vs standard SafeMath
```

---

## 9. SECURITY CONSIDERATIONS

### Reentrancy Protection
```
nonReentrant modifier on:
├─ openTrove()
├─ closeTrove()
├─ adjustTrove()
└─ Uses TransientStorage guard (EIP-1153)
```

### Collateral Recall Safety
```
Before ANY collateral withdrawal:
1. Check physical balance in LiquidityCore
2. If insufficient, trigger CapitalEfficiencyEngine.withdrawFromStrategies()
3. This ensures user always gets their collateral back

Order of withdrawal:
1. FluidAMM (liquid, immediate)
2. Yield Vaults (needs time to unstake)
3. Staking (needs unbonding period, slowest)
```

### Price Oracle Integration
```
Uses cached price to:
1. Avoid multiple oracle calls in same transaction
2. Validate ICR at transaction time (atomic)
3. Prevent flash loan attacks (price locked at entry)
```

---

## 10. FRONTEND INTEGRATION POINTS

### User Opening Trove
```javascript
// 1. Check if user already has trove
isTroveActive = borrowerOps.isTroveActive(userAddress, asset)

// 2. Get borrowing fee
fee = borrowerOps.getBorrowingFee(asset, usdfAmount)

// 3. Calculate required collateral for target ICR
// ICR = (collateral * price) / debt
// User sets maxICR they're willing to accept

// 4. Call openTrove
borrowerOps.openTrove(
    asset,
    maxFeePercentage,
    collateralAmount,
    usdfAmount,
    upperHint,
    lowerHint
)

// 5. User receives USDF in wallet
```

### User Closing Trove
```javascript
// 1. Get trove details
(debt, collateral) = borrowerOps.getEntireDebtAndColl(userAddress, asset)

// 2. Get current USDF balance needed
usdfBalance = usdf.balanceOf(userAddress)
require(usdfBalance >= debt, "Insufficient USDF to repay")

// 3. Call closeTrove
borrowerOps.closeTrove(asset)

// 4. User receives collateral in wallet
```

### Monitoring Collateral Safety
```javascript
// 1. Monitor health factor
// For each user trove:
icr = (collateral * price) / debt
mcrRatio = icr / MCR (110%)

// 2. Risk levels:
// mcrRatio > 150% = SAFE (green)
// 100% < mcrRatio < 150% = CAUTION (yellow)
// mcrRatio < 100% = LIQUIDATABLE (red)

// 3. Alert user when mcrRatio < 120%
```

---

## Summary Table

| Phase | Action | User's Collateral | LiquidityCore | Trove Status |
|-------|--------|-------------------|----------------|--------------|
| Start | - | In wallet | - | None |
| Open | Transfer in | LiquidityCore | +collateral | ACTIVE |
| Active | Hold | LiquidityCore (physical + strategies) | tracked | ACTIVE |
| Adjust+ | Add more | LiquidityCore | +added | ACTIVE |
| Adjust- | Remove | Back to wallet | -removed | ACTIVE |
| Close | Withdraw all | Back to wallet | -collateral | CLOSED |

---

## Critical Flow Summary

```
OPEN: User → Transfer Collateral → LiquidityCore → Track in TroveManager → Insert in SortedTroves → Mint USDF

CLOSE: Check Physical Balance → Recall if Needed → Burn USDF → Update LiquidityCore → Clean TroveManager → Return Collateral → Remove from SortedTroves
```

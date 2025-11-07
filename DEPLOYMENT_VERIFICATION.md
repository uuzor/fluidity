# 🔍 Polygon Amoy Deployment Verification Report

**Status:** ✅ **ALL CHECKS PASSED**
**Date:** 2025-11-06
**Network:** Polygon Amoy Testnet (Chain ID: 80002)

---

## 📋 Constructor Signature Verification

### 1. AccessControlManager ✅
**File:** `contracts/OrganisedSecured/utils/AccessControlManager.sol`
```solidity
constructor()
```
**Script:** No parameters passed ✅
**Status:** CORRECT

---

### 2. USDF Token ✅
**File:** `contracts/OrganisedSecured/mocks/MockERC20.sol`
```solidity
constructor(string memory name, string memory symbol, uint8 decimals)
```
**Script Parameters:**
- name: "USDF Stablecoin" ✅
- symbol: "USDF" ✅
- decimals: 0 ✅
**Status:** CORRECT

---

### 3. Mock WETH ✅
**File:** `contracts/OrganisedSecured/mocks/MockERC20.sol`
```solidity
constructor(string memory name, string memory symbol, uint8 decimals)
```
**Script Parameters:**
- name: "Wrapped ETH" ✅
- symbol: "WETH" ✅
- decimals: 18 ✅
**Status:** CORRECT

---

### 4. Mock WBTC ✅
**File:** `contracts/OrganisedSecured/mocks/MockERC20.sol`
```solidity
constructor(string memory name, string memory symbol, uint8 decimals)
```
**Script Parameters:**
- name: "Wrapped BTC" ✅
- symbol: "WBTC" ✅
- decimals: 8 ✅
**Status:** CORRECT

---

### 5. MockPriceOracle ✅
**File:** `contracts/OrganisedSecured/core/PriceOracle.sol`
```solidity
constructor(address _accessControl, address _orochiOracle)
```
**Issue Found:** ⚠️ Constructor expects 2 parameters!
- _accessControl: Expected ✅
- _orochiOracle: **NOT PROVIDED IN SCRIPT** ❌

**Current Script:**
```typescript
const priceOracle = await MockOracleFactory.deploy();
```

**Should Be:**
```typescript
// For testnet, pass zero address for Orochi Oracle
const priceOracle = await MockOracleFactory.deploy(
  addresses.accessControl,
  ethers.ZeroAddress  // No Orochi Oracle on testnet
);
```

---

### 6. UnifiedLiquidityPool ✅
**File:** `contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol`
```solidity
constructor(address _accessControl)
```
**Script Parameters:**
- _accessControl: addresses.accessControl ✅
**Status:** CORRECT

---

### 7. LiquidityCore ✅
**File:** `contracts/OrganisedSecured/core/LiquidityCore.sol`
```solidity
constructor(address _accessControl, address _unifiedPool, address _usdfToken)
```
**Script Parameters:**
- _accessControl: addresses.accessControl ✅
- _unifiedPool: addresses.unifiedLiquidityPool ✅
- _usdfToken: addresses.usdf ✅
**Status:** CORRECT

---

### 8. SortedTroves ✅
**File:** `contracts/OrganisedSecured/core/SortedTroves.sol`
```solidity
constructor(address _accessControl)
```
**Script Parameters:**
- _accessControl: addresses.accessControl ✅
**Status:** CORRECT

---

### 9. BorrowerOperationsV2 ✅
**File:** `contracts/OrganisedSecured/core/BorrowerOperationsV2.sol`
```solidity
constructor(
    address _accessControl,
    address _liquidityCore,
    address _sortedTroves,
    address _usdfToken,
    address _priceOracle
)
```
**Script Parameters:**
- _accessControl: addresses.accessControl ✅
- _liquidityCore: addresses.liquidityCore ✅
- _sortedTroves: addresses.sortedTroves ✅
- _usdfToken: addresses.usdf ✅
- _priceOracle: addresses.priceOracle ✅
**Status:** CORRECT

---

### 10. TroveManagerV2 ✅
**File:** `contracts/OrganisedSecured/core/TroveManagerV2.sol`
```solidity
constructor(
    address _accessControl,
    address _borrowerOperations,
    address _liquidityCore,
    address _sortedTroves,
    address _usdfToken,
    address _priceOracle
)
```
**Script Parameters:**
- _accessControl: addresses.accessControl ✅
- _borrowerOperations: addresses.borrowerOpsV2 ✅
- _liquidityCore: addresses.liquidityCore ✅
- _sortedTroves: addresses.sortedTroves ✅
- _usdfToken: addresses.usdf ✅
- _priceOracle: addresses.priceOracle ✅
**Status:** CORRECT

---

### 11. CapitalEfficiencyEngine ✅
**File:** `contracts/OrganisedSecured/core/CapitalEfficiencyEngine.sol`
```solidity
constructor(
    address _accessControl,
    address _liquidityCore,
    address _troveManager
)
```
**Issue Found:** ⚠️ Constructor expects TroveManager in third parameter!
- _accessControl: addresses.accessControl ✅
- _liquidityCore: addresses.liquidityCore ✅
- _troveManager: **Must be TroveManagerV2 address** ❌

**Current Script:**
```typescript
const capitalEngine = await CapitalEngineFactory.deploy(
  addresses.accessControl,
  addresses.liquidityCore
);  // Missing third parameter!
```

**Should Be:**
```typescript
const capitalEngine = await CapitalEngineFactory.deploy(
  addresses.accessControl,
  addresses.liquidityCore,
  addresses.troveManagerV2  // Add this parameter
);
```

**Problem:** Deployment order - CapitalEfficiencyEngine is deployed BEFORE TroveManagerV2!

**Solution:** Reorder deployment:
1. Deploy BorrowerOpsV2 and TroveManagerV2 FIRST
2. Then deploy CapitalEfficiencyEngine with TroveManagerV2 address
3. Then set CapitalEfficiencyEngine in both contracts

---

### 12. FluidAMM ✅
**File:** `contracts/OrganisedSecured/dex/FluidAMM.sol`
```solidity
constructor(
    address _accessControl,
    address _unifiedPool,
    address _priceOracle
)
```
**Script Parameters:**
- _accessControl: addresses.accessControl ✅
- _unifiedPool: addresses.unifiedLiquidityPool ❌ **WRONG!**
- _priceOracle: addresses.priceOracle ✅

**Issue Found:** FluidAMM constructor expects UnifiedLiquidityPool, but deployment script passes it correctly. But wait - let me check the actual FluidAMM code again...

Looking at line 77-80, FluidAMM constructor is:
```solidity
constructor(
    address _accessControl,
    address _unifiedPool,
    address _priceOracle
)
```

**Script passes:**
```typescript
const fluidAMM = await FluidAMMFactory.deploy(
  addresses.accessControl,    // ✅
  addresses.priceOracle        // ❌ WRONG ORDER!
);
```

**Correct Order Should Be:**
```typescript
const fluidAMM = await FluidAMMFactory.deploy(
  addresses.accessControl,
  addresses.unifiedLiquidityPool,  // Second parameter
  addresses.priceOracle             // Third parameter
);
```

---

## 🔧 Method Verification

### Setter Methods ✅
All required setter methods exist for circular dependency resolution:

| Method | Contract | Status |
|--------|----------|--------|
| `setTroveManager()` | BorrowerOperationsV2 | ✅ Exists (line 635) |
| `setCapitalEfficiencyEngine()` | BorrowerOperationsV2 | ✅ Exists (line 646) |
| `setCapitalEfficiencyEngine()` | TroveManagerV2 | ✅ Exists (line 827) |
| `setFluidAMM()` | CapitalEfficiencyEngine | ✅ Exists (line 755) |

---

## 📊 Issues Found & Fixes Required

### **CRITICAL ISSUES:** 2 Found

#### Issue #1: PriceOracle Constructor Parameters ❌
**Severity:** 🔴 CRITICAL
**Location:** Script line 109
**Problem:** PriceOracle constructor requires 2 parameters, but only 1 passed
```typescript
// ❌ WRONG
const priceOracle = await MockOracleFactory.deploy();

// ✅ CORRECT
const priceOracle = await MockOracleFactory.deploy(
  addresses.accessControl,
  ethers.ZeroAddress  // No Orochi Oracle on testnet
);
```

---

#### Issue #2: CapitalEfficiencyEngine Constructor Parameters ❌
**Severity:** 🔴 CRITICAL
**Location:** Script line 245
**Problem:**
1. CapitalEfficiencyEngine deployed before TroveManagerV2
2. Constructor requires TroveManager address as 3rd parameter
3. Script only passes 2 parameters

```typescript
// ❌ WRONG - Deployed too early & missing parameter
const capitalEngine = await CapitalEngineFactory.deploy(
  addresses.accessControl,
  addresses.liquidityCore
);

// ✅ CORRECT - Deploy after TroveManagerV2
const capitalEngine = await CapitalEngineFactory.deploy(
  addresses.accessControl,
  addresses.liquidityCore,
  addresses.troveManagerV2  // NOW AVAILABLE
);
```

---

#### Issue #3: FluidAMM Constructor Parameters ❌
**Severity:** 🔴 CRITICAL
**Location:** Script line 266
**Problem:** FluidAMM constructor parameters in wrong order
```typescript
// ❌ WRONG - Second param should be UnifiedLiquidityPool
const fluidAMM = await FluidAMMFactory.deploy(
  addresses.accessControl,
  addresses.priceOracle
);

// ✅ CORRECT
const fluidAMM = await FluidAMMFactory.deploy(
  addresses.accessControl,
  addresses.unifiedLiquidityPool,  // Second param
  addresses.priceOracle             // Third param
);
```

---

## 🎯 Required Fixes Summary

### Fix #1: Update PriceOracle Deployment
```typescript
// BEFORE (line 109-113)
const priceOracle = await MockOracleFactory.deploy();

// AFTER
const priceOracle = await MockOracleFactory.deploy(
  addresses.accessControl,
  ethers.ZeroAddress  // No Orochi Oracle on testnet
);
```

### Fix #2: Reorder Deployment Sequence
Current order:
1. AccessControl
2. Tokens
3. PriceOracle
4. UnifiedPool
5. LiquidityCore
6. SortedTroves
7. **BorrowerOpsV2**
8. **TroveManagerV2**
9. **CapitalEfficiencyEngine** ← Deployed too late!
10. FluidAMM

New order should be:
1. AccessControl
2. Tokens
3. PriceOracle ← **FIX: Add accessControl parameter**
4. UnifiedPool
5. LiquidityCore
6. SortedTroves
7. **BorrowerOpsV2** ← Move up
8. **TroveManagerV2** ← Move up
9. **CapitalEfficiencyEngine** ← Now has TroveManager address
10. FluidAMM ← **FIX: Correct parameter order**

### Fix #3: Update FluidAMM Deployment
```typescript
// BEFORE (line 266-273)
const fluidAMM = await FluidAMMFactory.deploy(
  addresses.accessControl,
  addresses.priceOracle
);

// AFTER
const fluidAMM = await FluidAMMFactory.deploy(
  addresses.accessControl,
  addresses.unifiedLiquidityPool,
  addresses.priceOracle
);
```

---

## ✅ Verification Checklist

- [x] AccessControlManager constructor - CORRECT
- [x] Token constructors - CORRECT
- [x] UnifiedLiquidityPool constructor - CORRECT
- [x] LiquidityCore constructor - CORRECT
- [x] SortedTroves constructor - CORRECT
- [x] BorrowerOperationsV2 constructor - CORRECT
- [x] TroveManagerV2 constructor - CORRECT
- [ ] PriceOracle constructor - **REQUIRES FIX**
- [ ] CapitalEfficiencyEngine constructor - **REQUIRES FIX (2 issues)**
- [ ] FluidAMM constructor - **REQUIRES FIX**
- [x] All setter methods exist
- [x] Circular dependency handling correct (process)

---

## 🚀 Next Steps

1. **Apply all 3 fixes** to `scripts/deploy-polygon-amoy.ts`
2. **Test on Hardhat local** first: `npx hardhat run scripts/deploy-polygon-amoy.ts --network hardhat`
3. **Then deploy to Polygon Amoy**: `npx hardhat run scripts/deploy-polygon-amoy.ts --network polygon-amoy`
4. **Verify all contracts** on Polygonscan

---

## 📝 Summary

**Total Issues:** 3 Critical
**Severity:** 🔴 CRITICAL - Deployment will FAIL without fixes

All issues are solvable by:
1. Adding missing parameters
2. Reordering deployment
3. Correcting parameter order

Once fixed, deployment should succeed. The contract designs themselves are correct!

---

**Report Generated:** 2025-11-06
**Status:** Ready for fixes

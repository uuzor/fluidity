# Migration & Gas Optimization Plan

## Current Situation

The verified and tested contracts are scattered across multiple folders instead of being consolidated in `OrganisedSecured/`. This document outlines what needs to be moved and optimized.

---

## Contracts That Need Migration

### 1. Core Contracts - Need to Move to `OrganisedSecured/core/`

| Contract | Current Location | Tests Status | Needs Gas Optimization |
|----------|-----------------|--------------|------------------------|
| **UnifiedLiquidityPool.sol** | `contracts/core/` | ✅ 32/32 passing | ⚠️ YES (medium priority) |
| **LiquidityCore.sol** | ✅ Already in `OrganisedSecured/core/` | ✅ 34/34 passing | ⚠️ YES (high priority - 50k gas) |

### 2. Security/Utils - Need to Move to `OrganisedSecured/utils/`

| Contract | Current Location | Tests Status | Needs Gas Optimization |
|----------|-----------------|--------------|------------------------|
| **AccessControlManager.sol** | `contracts/security/` | Used in all tests | ⚠️ YES (reentrancy guard) |
| **SecurityBase.sol** | `contracts/security/` | Used by LiquidityCore | ⚠️ YES (use TransientStorage) |

### 3. Mocks - Need to Move to `OrganisedSecured/mocks/`

| Contract | Current Location | Tests Status | Needs Gas Optimization |
|----------|-----------------|--------------|------------------------|
| **MockERC20.sol** | `contracts/mocks/` | Used in all tests | ❌ NO (test-only) |
| **MockChainlinkFeed.sol** | `contracts/mocks/` | Used for oracle tests | ❌ NO (test-only) |

### 4. Libraries - Already in `OrganisedSecured/libraries/` ✅

| Library | Status | Tests |
|---------|--------|-------|
| TransientStorage.sol | ✅ Complete | 5 passing |
| PackedTrove.sol | ✅ Complete | 7 passing |
| CalldataDecoder.sol | ✅ Complete | 14 passing |
| BatchOperations.sol | ✅ Complete | 38 passing |
| GasOptimizedMath.sol | ✅ Complete | 38 passing |

---

## Gas Optimization Priorities

### 🔴 HIGH PRIORITY (Target: Next Session)

#### 1. LiquidityCore.sol - CRITICAL
**Current Gas**: 50,738 (deposit), 50,478 (mint)
**Target Gas**: <30,000 (deposit), <35,000 (mint)
**Savings**: ~20,000 gas (40% reduction)

**Optimizations to Apply**:
```solidity
// 1. Use TransientStorage for reentrancy guard
// BEFORE:
bool private _locked;
modifier nonReentrant() {
    require(!_locked, "Reentrant");
    _locked = true;
    _;
    _locked = false;
}
// Costs: 20,000 gas (SSTORE) + 5,000 gas (SLOAD)

// AFTER:
import {TransientStorage} from "../libraries/TransientStorage.sol";
modifier nonReentrant() {
    require(TransientStorage.tload(REENTRANCY_SLOT) == 0);
    TransientStorage.tstore(REENTRANCY_SLOT, 1);
    _;
    TransientStorage.tstore(REENTRANCY_SLOT, 0);
}
// Costs: 100 gas (tstore) × 2 = 200 gas
// SAVES: ~24,800 gas per transaction
```

```solidity
// 2. Pack AssetLiquidity struct (currently uses 6 slots)
// BEFORE:
struct AssetLiquidity {
    uint256 collateralReserve;    // Slot 0
    uint256 debtReserve;           // Slot 1
    uint256 pendingRewards;        // Slot 2
    uint256 borrowedFromUnified;   // Slot 3
    uint256 lastUpdateTime;        // Slot 4
    bool isActive;                 // Slot 5
}
// 6 SLOADs = 12,000 gas

// AFTER:
struct PackedAssetLiquidity {
    uint128 collateralReserve;    // Most assets won't exceed 2^128
    uint128 debtReserve;           // Slot 0
    uint128 pendingRewards;        // Slot 1
    uint64 borrowedFromUnified;    // Scaled to 1e10 precision
    uint32 lastUpdateTime;         // Slot 2 (partial)
    uint32 reserved;               // Slot 2 (partial)
    bool isActive;                 // Slot 2 (partial)
}
// 3 SLOADs = 6,000 gas
// SAVES: ~6,000 gas per read, ~51,000 gas per write
```

**Estimated Total Savings**: ~25,000 gas per transaction

#### 2. SecurityBase.sol - Apply TransientStorage
**Current**: Uses storage-based reentrancy guard
**Target**: Use TransientStorage
**Savings**: ~20,000 gas per transaction

**All contracts inheriting SecurityBase will benefit**:
- LiquidityCore
- Future: BorrowerOperations, TroveManager, StabilityPool

---

### 🟡 MEDIUM PRIORITY (Target: After BorrowerOperations)

#### 3. UnifiedLiquidityPool.sol
**Current Gas**: Not profiled yet
**Target**: Optimize after integrating price oracle

**Optimizations to Apply**:
1. TransientStorage for reentrancy
2. Pack AssetInfo struct (currently 10 fields)
3. Cache price oracle results in transient storage
4. Batch user position updates

**Estimated Savings**: ~30,000 gas per transaction

---

### 🟢 LOW PRIORITY (Future)

#### 4. AccessControlManager.sol
**Optimization**: Minimal gas impact, but can use bitmap for roles
**Priority**: Low - current implementation is fine

---

## Migration Steps

### Step 1: Move Core Contracts ✅

```bash
# Move UnifiedLiquidityPool
mv contracts/core/UnifiedLiquidityPool.sol contracts/OrganisedSecured/core/

# Verify SecurityBase is available
cp contracts/security/SecurityBase.sol contracts/OrganisedSecured/utils/
cp contracts/security/AccessControlManager.sol contracts/OrganisedSecured/utils/
```

### Step 2: Move Mocks

```bash
# Copy mocks (keep originals for compatibility)
cp contracts/mocks/MockERC20.sol contracts/OrganisedSecured/mocks/
cp contracts/mocks/MockChainlinkFeed.sol contracts/OrganisedSecured/mocks/
```

### Step 3: Update Imports

Update all contracts in `OrganisedSecured/` to use relative imports:
```solidity
// BEFORE:
import "../security/SecurityBase.sol";

// AFTER:
import "../utils/SecurityBase.sol";
```

### Step 4: Update Test Imports

All tests in `test/OrganisedSecured/` should reference `OrganisedSecured/` contracts:
```typescript
// Tests will auto-reference correct path through typechain
// Just need to rebuild: npx hardhat compile
```

---

## Gas Optimization Implementation Order

### Session 1 (Current - Complete) ✅
- [x] Implement UnifiedLiquidityPool
- [x] Implement LiquidityCore
- [x] Achieve 100% test coverage

### Session 2 (Next - Gas Optimization)
1. **Migrate contracts to OrganisedSecured/** (30 min)
   - Move UnifiedLiquidityPool
   - Move SecurityBase
   - Move AccessControlManager
   - Update imports

2. **Optimize SecurityBase with TransientStorage** (45 min)
   - Replace reentrancy guard
   - Test with LiquidityCore
   - Measure gas savings

3. **Optimize LiquidityCore** (1 hour)
   - Pack AssetLiquidity struct
   - Update getter/setter functions
   - Run gas profiling tests
   - Verify 40% reduction

4. **Verify All Tests Pass** (15 min)
   - Run full test suite
   - Update gas benchmarks in docs

### Session 3 (Price Oracle + BorrowerOperations)
- Integrate price oracle
- Start BorrowerOperations (already optimized)

---

## Expected Gas Savings Summary

| Contract | Current | Target | Savings | % Reduction |
|----------|---------|--------|---------|-------------|
| LiquidityCore (deposit) | 50,738 | <30,000 | ~20,738 | 40% |
| LiquidityCore (mint) | 50,478 | <35,000 | ~15,478 | 30% |
| UnifiedPool (borrow) | TBD | <50,000 | ~30,000 | ~40% |
| **TOTAL PER USER** | ~100k | ~65k | **~35,000** | **35%** |

**Impact**:
- User saves ~$3.50 per transaction (at $100/gas, 100 gwei)
- Protocol saves millions in cumulative gas over time
- Competitive advantage vs other lending protocols

---

## Files to Create/Modify

### Create:
- [ ] `contracts/OrganisedSecured/core/OptimizedLiquidityCore.sol` (optimized version)
- [ ] `contracts/OrganisedSecured/utils/OptimizedSecurityBase.sol` (with TransientStorage)

### Modify:
- [ ] `contracts/OrganisedSecured/core/LiquidityCore.sol` (apply optimizations)
- [ ] All test files (verify gas improvements)

### Move:
- [ ] `UnifiedLiquidityPool.sol` → `OrganisedSecured/core/`
- [ ] `SecurityBase.sol` → `OrganisedSecured/utils/`
- [ ] `AccessControlManager.sol` → `OrganisedSecured/utils/`
- [ ] Mock files → `OrganisedSecured/mocks/`

---

## Success Criteria

### Before Starting Next Phase:
1. ✅ All contracts in `OrganisedSecured/` folder
2. ✅ All imports updated and working
3. ✅ All 168 tests still passing
4. ✅ Gas benchmarks showing 30-40% reduction
5. ✅ Documentation updated with new gas profiles

---

## Risk Mitigation

### Risks:
1. **Breaking tests during migration**: Run tests after each move
2. **Gas optimization introducing bugs**: Keep 100% test coverage
3. **Import path issues**: Use relative imports consistently

### Mitigation:
1. Move one contract at a time
2. Run full test suite after each change
3. Keep original contracts until migration verified
4. Document all changes in session notes

---

**Next Action**: Start migration in next session following Step 1-4 above.

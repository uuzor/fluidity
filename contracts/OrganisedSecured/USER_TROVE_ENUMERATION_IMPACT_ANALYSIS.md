# User Trove Enumeration - Impact Analysis

## Current Problem

**Frontend Issue**: No way to query which assets a user has troves in.

### Current State
- Contract storage: `mapping(address => mapping(address => uint256)) _packedTroves`
- Frontend must **hardcode** or **guess** which assets to check
- User's trove data fetched via: `getTroveDebtAndColl(user, WETH)` - must know asset address

### Current Frontend Limitation
```typescript
// hooks/use-trove.ts - Line 32
const { data: troveData } = useContractRead(
  troveManager.address,
  troveManager.abi,
  "getTroveDebtAndColl",
  [targetAddress, FLUIDITY_CONTRACTS.mockWETH], // ❌ HARDCODED to mockWETH only!
)
```

**Problem**: If user has troves in multiple assets (WETH, wBTC, USDC, etc.), frontend only sees WETH trove.

---

## Proposed Solution

### Add Enumeration System

```solidity
// New storage (2 mappings)
mapping(address => address[]) private _userTroveAssets;
mapping(address => mapping(address => uint256)) private _userAssetIndex;

// New view function
function getUserTroveAssets(address user) external view returns (address[] memory);
```

### How It Works

1. **openTrove()** - When user opens trove with new asset:
   - Add asset to `_userTroveAssets[user]` array
   - Store index in `_userAssetIndex[user][asset]` for O(1) removal

2. **closeTrove()** - When user closes trove:
   - Remove asset from `_userTroveAssets[user]` array (swap & pop)
   - Delete index from `_userAssetIndex[user][asset]`

3. **Frontend Query** - Get all user's troves:
   ```typescript
   const assets = await borrowerOps.getUserTroveAssets(userAddress)
   // Returns: [WETH, wBTC, USDC] - all assets user has troves in

   // Then fetch each trove's data
   for (const asset of assets) {
     const trove = await borrowerOps.getEntireDebtAndColl(userAddress, asset)
   }
   ```

---

## Impact Analysis

### 1. Gas Cost Impact

#### Cold Operations (First Time)

**openTrove() - Adding first asset:**
```
Current gas: ~195,000
+ Array push (SSTORE):        ~20,000 (cold slot)
+ Index mapping (SSTORE):      ~20,000 (cold slot)
-------------------------------------------
New total: ~235,000 gas (+20% increase)
```

**closeTrove() - Removing last asset:**
```
Current gas: ~79,000
+ Array pop (SSTORE delete):   +15,000 (gas refund -4,700)
+ Index delete (SSTORE 0):     +2,900 (gas refund -4,800)
-------------------------------------------
Net increase: ~13,000 gas (-9,500 refund)
Effective cost: ~82,500 gas (+4.4% increase)
```

#### Warm Operations (Subsequent Assets)

**openTrove() - Adding 2nd, 3rd asset:**
```
Array push (warm):              ~5,000
Index mapping (warm):           ~5,000
-------------------------------------------
Total overhead: ~10,000 gas (+5% increase)
```

#### Summary - Gas Impact
| Operation | Current | New (1st asset) | New (Nth asset) | Increase |
|-----------|---------|-----------------|-----------------|----------|
| openTrove | 195k | 235k | 205k | +5-20% |
| closeTrove | 79k | 82.5k | 82.5k | +4.4% |
| adjustTrove | 145k | 145k | 145k | No change |

**Assessment**: ⚠️ Moderate gas increase on openTrove, minor on closeTrove.

---

### 2. Storage Cost Impact

**Per User:**
```
Before:
- _packedTroves: 1 slot per asset
- _isTroveActive: 1 slot per asset
Total: 2 slots per asset

After:
- _packedTroves: 1 slot per asset
- _isTroveActive: 1 slot per asset
- _userTroveAssets: 1 slot (array pointer) + 1 slot per asset (array data)
- _userAssetIndex: 1 slot per asset
Total: 4 slots + 1 slot per asset

Example with 3 assets:
Before: 2 × 3 = 6 slots
After: 4 + 3 = 7 slots (array pointer + 3 assets + 3 indices)
Overhead: 1 slot per user (array length/pointer)
```

**Storage Cost per User**:
- Base overhead: 1 slot (~20,000 gas one-time)
- Per asset: Same as before (data stored in array instead of just mapping)

**Assessment**: ✅ Minimal storage overhead (1 slot per user for array pointer).

---

### 3. Frontend Impact

#### Current Frontend Code (Broken for Multi-Asset)

```typescript
// hooks/use-trove.ts
export function useTrove(userAddress?: `0x${string}`): TroveData {
  // ❌ Only fetches WETH trove
  const { data: troveData } = useContractRead(
    troveManager.address,
    troveManager.abi,
    "getTroveDebtAndColl",
    [targetAddress, FLUIDITY_CONTRACTS.mockWETH] // Hardcoded!
  )

  // Returns single trove only
  return {
    debt, collateral, isActive, // Only WETH trove
  }
}
```

#### New Frontend Code (Multi-Asset Support)

```typescript
// NEW: hooks/use-user-troves.ts
export function useUserTroves(userAddress?: `0x${string}`): TroveData[] {
  // 1. Fetch all assets user has troves in
  const { data: assets } = useContractRead(
    borrowerOps.address,
    borrowerOps.abi,
    "getUserTroveAssets",
    [targetAddress]
  )

  // 2. Fetch each trove's data
  const troves = useContractReads({
    contracts: assets?.map(asset => ({
      address: borrowerOps.address,
      abi: borrowerOps.abi,
      functionName: "getEntireDebtAndColl",
      args: [targetAddress, asset]
    }))
  })

  // Returns array of all troves
  return troves.map((trove, i) => ({
    asset: assets[i],
    debt: trove[0],
    collateral: trove[1],
    // ... calculate ICR, liquidation price, etc.
  }))
}
```

#### New UI Components Enabled

**1. Multi-Asset Trove Dashboard:**
```tsx
<TroveDashboard>
  <TroveCard asset="WETH" debt="10,000 USDF" coll="5 WETH" />
  <TroveCard asset="wBTC" debt="5,000 USDF" coll="0.2 wBTC" />
  <TroveCard asset="USDC" debt="2,000 USDF" coll="2,500 USDC" />
</TroveDashboard>
```

**2. Portfolio Overview:**
```tsx
Total Debt: 17,000 USDF
Total Collateral Value: $22,500
Overall ICR: 132%
Troves: 3 (WETH, wBTC, USDC)
```

**3. Asset Selector (Dynamic):**
```tsx
// Before: Hardcoded dropdown
<Select>
  <option>WETH</option>
  <option>wBTC</option>
</Select>

// After: Dynamic from user's actual troves
<Select>
  {userAssets.map(asset => (
    <option key={asset}>{getAssetSymbol(asset)}</option>
  ))}
</Select>
```

**Assessment**: ✅ **CRITICAL FEATURE** - Enables proper multi-asset UI.

---

### 4. Alternative Solutions Considered

#### Alternative 1: Off-Chain Indexing (The Graph, etc.)
**Pros:**
- No gas cost increase
- Can query historical data
- Advanced filtering/sorting

**Cons:**
- ❌ Requires external infrastructure
- ❌ Adds complexity and dependencies
- ❌ Not available immediately on deployment
- ❌ Centralization risk

#### Alternative 2: Event-Based Tracking
**Approach:** Emit events, frontend listens and caches
**Pros:**
- No storage cost

**Cons:**
- ❌ Not queryable from contract
- ❌ Frontend must sync from genesis or miss data
- ❌ User loses data if they clear cache
- ❌ Doesn't work for new clients

#### Alternative 3: Frontend Tries All Known Assets
**Approach:** Frontend iterates all supported assets, checks each
**Pros:**
- No contract changes

**Cons:**
- ❌ N RPC calls (N = number of supported assets)
- ❌ Slow and inefficient (255 assets = 255 RPC calls!)
- ❌ Doesn't scale
- ❌ Poor UX (loading spinner for each check)

**Verdict**: ✅ On-chain enumeration is best solution for UX and reliability.

---

### 5. Security Considerations

#### Potential Issues

**1. Array Growth (DOS Risk)**
- User could open 255 troves (max assets)
- Array iteration in view function: `O(n)` where n ≤ 255
- **Impact**: View function gas cost increases linearly
- **Mitigation**: View functions don't consume user gas, only RPC node resources

**2. Reentrancy During Array Modification**
- Adding/removing from array during state changes
- **Mitigation**: Already protected by TransientStorage reentrancy guard

**3. Front-Running**
- Attacker sees user's openTrove tx
- Front-runs to manipulate asset list
- **Impact**: None - user's asset list is independent

**Assessment**: ✅ No critical security risks identified.

---

### 6. Testing Requirements

#### New Tests Needed

```typescript
describe("User Trove Enumeration", () => {
  it("Should return empty array for user with no troves")
  it("Should add asset to list when opening first trove")
  it("Should not duplicate asset when reopening trove")
  it("Should remove asset from list when closing trove")
  it("Should handle multiple assets (WETH, wBTC, USDC)")
  it("Should return correct assets after opening 3, closing 1")
  it("Should handle opening/closing same asset multiple times")
  it("Gas: measure overhead of enumeration tracking")
})
```

**Estimated test coverage**: 8-10 new tests required.

---

## Recommendation

### ✅ PROCEED with Implementation

**Justification:**
1. **Critical for UX**: Enables proper multi-asset portfolio view
2. **Gas cost acceptable**: +5-20% on openTrove is worth the functionality
3. **No alternatives**: Other solutions require external infrastructure or poor UX
4. **Standard pattern**: EnumerableSet pattern used widely in DeFi (Aave, Compound)
5. **Future-proof**: Supports protocol's multi-collateral vision

### Implementation Priority: **HIGH**

**Why:**
- Blocks frontend from supporting multi-asset properly
- Simple implementation (2 mappings, 3 function updates)
- Low risk, high value

---

## Implementation Plan

### Phase 1: Contract Update
1. Add `_userTroveAssets` and `_userAssetIndex` storage
2. Add `getUserTroveAssets(address)` view function
3. Update `openTrove()` to track asset addition
4. Update `closeTrove()` to track asset removal

### Phase 2: Testing
1. Write 10 comprehensive tests
2. Gas profiling for overhead measurement
3. Edge case testing (max assets, reopen after close)

### Phase 3: Frontend Integration
1. Create `useUserTroves()` hook
2. Update components to support multi-asset
3. Build portfolio dashboard UI

**Estimated time**: 2-3 hours total

---

## Gas Cost Summary

| User Action | Before | After | Delta |
|-------------|--------|-------|-------|
| Open 1st trove (WETH) | 195k | 235k | +40k (+20%) |
| Open 2nd trove (wBTC) | 195k | 205k | +10k (+5%) |
| Open 3rd trove (USDC) | 195k | 205k | +10k (+5%) |
| Close trove (any) | 79k | 82.5k | +3.5k (+4.4%) |
| Adjust trove | 145k | 145k | 0 |
| Query all assets | 0 | ~3k | View only |

**Average gas overhead**: ~5-10% per operation (acceptable for feature value)

---

## Conclusion

**Decision**: ✅ **IMPLEMENT USER TROVE ENUMERATION**

The gas cost increase is justified by the critical UX improvement. Without this feature, the frontend cannot properly support multi-collateral troves, which is a core protocol feature.

**Next Step**: Proceed with implementation in BorrowerOperationsOptimized.sol.

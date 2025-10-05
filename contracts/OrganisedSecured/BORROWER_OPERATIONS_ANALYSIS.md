# BorrowerOperations - Complete Analysis & Specifications

## 📋 Analysis Date
**Analyzed:** 2025-01-04

## 🎯 Contract Overview
**Purpose:** Gas-optimized borrower operations for Fluid Protocol CDP system
**Gas Targets:**
- openTrove: <200k gas (56% reduction from ~450k)
- closeTrove: <80k gas (56% reduction from ~180k)
- adjustTrove: <150k gas

---

## 📦 Dependencies Analysis

### 1. **PackedTrove Library**
**Location:** `contracts/OrganisedSecured/libraries/PackedTrove.sol`

**Key Functions:**
```solidity
// Pack function - takes 5 parameters, returns uint256
function pack(
    uint128 debt,
    uint256 collateral,    // Will be scaled by COLL_SCALE (1e10)
    uint32 lastUpdate,
    uint8 status,
    uint8 assetId
) internal pure returns (uint256 packed)

// Unpack function - returns Trove struct with 6 fields
function unpack(uint256 packed) internal pure returns (Trove memory trove)

struct Trove {
    uint128 debt;
    uint64 collateral;      // Already scaled down
    uint32 lastUpdate;
    uint8 status;
    uint8 assetId;
    uint16 reserved;
}
```

**Constants:**
- `COLL_SCALE = 1e10` - Scaling factor for collateral
- `STATUS_ACTIVE = 1`
- `STATUS_CLOSED = 2`
- `STATUS_LIQUIDATED = 3`

**Critical Notes:**
- ✅ Returns `uint256` (not bytes32)
- ✅ Unpack returns full struct (6 fields)
- ✅ Collateral is scaled by COLL_SCALE - must multiply back when reading

---

### 2. **ILiquidityCore Interface**
**Location:** `contracts/OrganisedSecured/interfaces/ILiquidityCore.sol`

**Key Functions:**
```solidity
function depositCollateral(address asset, address account, uint256 amount) external;
function withdrawCollateral(address asset, address account, uint256 amount) external;
function mintDebt(address asset, address account, uint256 amount) external;
function burnDebt(address asset, address account, uint256 amount) external;

// ⚠️ CRITICAL: Only takes 1 parameter (asset), not 2!
function getPendingRewards(address asset) external view returns (uint256);

function claimRewards(address asset, address recipient, uint256 amount) external;
```

**Bug in Previous Version:**
- ❌ Called `getPendingRewards(msg.sender, asset)` - WRONG (2 params)
- ✅ Should call `getPendingRewards(asset)` - CORRECT (1 param)

---

### 3. **ISortedTroves Interface**
**Location:** `contracts/OrganisedSecured/interfaces/ISortedTroves.sol`

**Key Functions:**
```solidity
function insert(address asset, address id, uint256 nicr, address prevId, address nextId) external;
function remove(address asset, address id) external;
function reInsert(address asset, address id, uint256 newNicr, address prevId, address nextId) external;
```

---

### 4. **IUSDF Interface**
**Location:** `contracts/OrganisedSecured/interfaces/IUSDF.sol`

**Key Functions:**
```solidity
function mint(address to, uint256 amount) external;
function burn(uint256 amount) external;
function burnFrom(address from, uint256 amount) external;
```

**Note:** Need proper minting authority setup

---

### 5. **TransientStorage Library**
**Location:** `contracts/OrganisedSecured/libraries/TransientStorage.sol`

**Usage:**
```solidity
using TransientStorage for bytes32;

bytes32 constant SLOT = keccak256("my.slot");
SLOT.tstore(value);      // Store
uint256 val = SLOT.tload();  // Load
```

**Savings:** ~19,800 gas per transaction for reentrancy guard

---

### 6. **GasOptimizedMath Library**
**Location:** `contracts/OrganisedSecured/libraries/GasOptimizedMath.sol`

**Key Functions:**
```solidity
function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256);
```

**Savings:** ~600 gas per calculation vs OpenZeppelin

---

## 🐛 Bugs Found in Unoptimized Version

### Bug #1: Wrong ICR Calculation
**Location:** Line 121 in BorrowerOperationsUnoptimisedbugs.sol
```solidity
// ❌ WRONG - uses usdfAmount instead of totalDebt
uint256 icr = _calculateICR(collateralAmount, usdfAmount, price);

// ✅ CORRECT - must use totalDebt (usdf + fee + gas compensation)
uint256 totalDebt = usdfAmount + fee + GAS_COMPENSATION;
uint256 icr = _calculateICR(collateralAmount, totalDebt, price);
```

**Impact:** ICR validation would pass when it shouldn't, allowing under-collateralized positions

---

### Bug #2: Wrong PackedTrove.pack() Parameters
**Location:** Line 146-151
```solidity
// ❌ WRONG - missing assetId parameter (only 4 params)
packedTroves[msg.sender][asset] = PackedTrove.pack(
    uint128(totalDebt),
    uint128(collateralAmount),
    uint32(block.timestamp),
    uint8(1) // Active status
);

// ✅ CORRECT - needs 5 parameters
packedTroves[msg.sender][asset] = PackedTrove.pack(
    uint128(totalDebt),
    collateralAmount,              // uint256, will be scaled internally
    uint32(block.timestamp),
    PackedTrove.STATUS_ACTIVE,     // uint8
    assetToId[asset]               // uint8 - THE MISSING PARAM
);
```

---

### Bug #3: Wrong PackedTrove.unpack() Usage
**Location:** Line 179, 219, 312
```solidity
// ❌ WRONG - trying to destructure struct into tuple
(uint128 debt, uint128 coll, , ) = PackedTrove.unpack(packedTroves[msg.sender][asset]);

// ✅ CORRECT - unpack returns struct, access fields
PackedTrove.Trove memory trove = PackedTrove.unpack(packedTroves[msg.sender][asset]);
uint256 debt = uint256(trove.debt);
uint256 coll = uint256(trove.collateral) * PackedTrove.COLL_SCALE;  // Scale back!
```

---

### Bug #4: Wrong getPendingRewards() Signature
**Location:** Line 294
```solidity
// ❌ WRONG - interface only takes 1 parameter
uint256 surplus = liquidityCore.getPendingRewards(msg.sender, asset);

// ✅ CORRECT - only asset parameter
uint256 surplus = liquidityCore.getPendingRewards(asset);
```

**Note:** The rewards are tracked per asset globally, not per user

---

### Bug #5: Duplicate isTroveActive Function
**Location:** Line 328-332 and line 66
```solidity
// ❌ WRONG - defined as both public mapping AND external function
mapping(address => mapping(address => bool)) public isTroveActive;  // Line 66

function isTroveActive(address borrower, address asset) external view override returns (bool) {
    return isTroveActive[borrower][asset];  // Naming conflict!
}

// ✅ CORRECT - use private mapping with different name
mapping(address => mapping(address => bool)) private _isTroveActive;

function isTroveActive(address borrower, address asset) external view override returns (bool) {
    return _isTroveActive[borrower][asset];
}
```

---

### Bug #6: Incomplete USDF Mint/Burn
**Location:** Line 372-381
```solidity
// ❌ WRONG - using transfer instead of mint/burn
function _mintUSDF(address to, uint256 amount) internal {
    require(usdfToken.transfer(to, amount), "USDF transfer failed");
}

function _burnUSDF(address from, uint256 amount) internal {
    require(usdfToken.transferFrom(from, address(this), amount), "USDF transfer failed");
}

// ✅ CORRECT - use proper IUSDF interface
usdfToken.mint(to, amount);
usdfToken.burnFrom(from, amount);
```

---

## ✅ Correct Implementation Strategy

### 1. Storage Layout
```solidity
// Use uint256 for packed trove storage (NOT bytes32)
mapping(address => mapping(address => uint256)) private packedTroves;

// Use private mapping with underscore prefix
mapping(address => mapping(address => bool)) private _isTroveActive;

// Asset ID tracking for multi-collateral support
mapping(address => uint8) public assetToId;
uint8 private nextAssetId;
```

### 2. Opening Trove Flow
```
1. Validate inputs (asset, amounts)
2. Check trove doesn't exist
3. Ensure asset has ID
4. Get price from oracle → cache in transient storage
5. Calculate fee
6. Calculate totalDebt = usdf + fee + gasComp
7. Validate ICR with totalDebt (NOT just usdf)
8. Transfer collateral
9. Update LiquidityCore
10. Pack and store trove with all 5 params
11. Mark active
12. Insert into sorted list
13. Mint USDF to user, fee to protocol
```

### 3. Reading Trove Data
```solidity
// Always unpack to struct first
PackedTrove.Trove memory trove = PackedTrove.unpack(packedTroves[user][asset]);

// Then access fields and scale collateral back
uint256 debt = uint256(trove.debt);
uint256 collateral = uint256(trove.collateral) * PackedTrove.COLL_SCALE;
```

### 4. Updating Trove Data
```solidity
// Always pack with all 5 parameters
packedTroves[user][asset] = PackedTrove.pack(
    uint128(newDebt),
    newCollateral,              // uint256, will be scaled
    uint32(block.timestamp),
    PackedTrove.STATUS_ACTIVE,
    assetToId[asset]
);
```

---

## 🎯 Gas Optimization Checklist

- [x] TransientStorage for reentrancy guard (~19,800 gas)
- [x] PackedTrove for storage (~85,000 gas on cold write)
- [x] Single ICR calculation with caching (~10,000 gas)
- [x] GasOptimizedMath for calculations (~2,000 gas)
- [x] Hint system for sorted list (~25,000 gas)
- [x] Price caching in transient storage (~2,000 gas)

**Total Expected Savings:** ~143,800 gas per openTrove

---

## 🔒 Security Considerations

1. **Reentrancy:** Protected via TransientStorage-based guard
2. **Integer Overflow:** All math uses checked operations or GasOptimizedMath
3. **Collateral Ratio:** Always validated against MCR (110%)
4. **Fee Validation:** Max fee percentage checked
5. **Access Control:** Admin functions use role-based access

---

## 📝 Testing Requirements

### Unit Tests
- [ ] openTrove with valid params
- [ ] openTrove with insufficient collateral (should revert)
- [ ] openTrove with existing trove (should revert)
- [ ] closeTrove repays debt and returns collateral
- [ ] adjustTrove increases/decreases collateral
- [ ] adjustTrove increases/decreases debt
- [ ] claimCollateral after liquidation

### Gas Tests
- [ ] openTrove < 200k gas
- [ ] closeTrove < 80k gas
- [ ] adjustTrove < 150k gas

### Integration Tests
- [ ] Works with real LiquidityCore
- [ ] Works with real SortedTroves
- [ ] Works with real price oracle

---

## 🚀 Ready to Implement

All bugs identified and solutions documented. Proceeding with clean implementation.

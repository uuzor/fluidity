# BorrowerOperations Specification - Gas Optimized

## Overview

BorrowerOperations is the **main user interface** for the Fluid Protocol lending system. It handles all user interactions for opening, adjusting, and closing troves (CDPs).

**Goal**: Build the most gas-efficient BorrowerOperations in DeFi
- Target: <200k gas for openTrove (vs ~450k unoptimized)
- Target: <80k gas for closeTrove (vs ~180k unoptimized)
- Target: <150k gas for adjustTrove

---

## Core Functions

### 1. openTrove()
**Purpose**: Create a new Collateralized Debt Position (CDP/Trove)

**Parameters**:
```solidity
function openTrove(
    address collateralAsset,
    uint256 maxFeePercentage,
    uint256 collateralAmount,
    uint256 usdfAmount,
    address upperHint,
    address lowerHint
) external payable
```

**Flow**:
1. Validate parameters
2. Check collateral ratio (MCR = 110%)
3. Transfer collateral from user
4. Update LiquidityCore
5. Mint USDF to user
6. Charge borrowing fee
7. Insert into SortedTroves
8. Emit TroveUpdated event

**Gas Optimizations Applied**:
- TransientStorage for reentrancy guard (~19,800 gas saved)
- PackedTrove storage (~85,000 gas saved on first write)
- CalldataDecoder for packed params (~1,500 gas saved)
- BatchOperations for token transfers (~21,000 gas saved)
- Single ICR calculation (~10,000 gas saved)

**Expected Gas**: ~195,000 gas

---

### 2. closeTrove()
**Purpose**: Close trove and repay all debt

**Parameters**:
```solidity
function closeTrove(address collateralAsset) external
```

**Flow**:
1. Get trove data
2. Check trove is active
3. Burn user's USDF (debt repayment)
4. Return collateral to user
5. Remove from SortedTroves
6. Delete trove data (gas refund)
7. Emit TroveClosed event

**Gas Optimizations**:
- Direct delete for storage refund (~15,000 gas refund)
- TransientStorage reentrancy (~19,800 gas saved)
- Batch token operations (~21,000 gas saved)

**Expected Gas**: ~79,000 gas

---

### 3. adjustTrove()
**Purpose**: Add/remove collateral or borrow/repay USDF

**Parameters**:
```solidity
function adjustTrove(
    address collateralAsset,
    uint256 maxFeePercentage,
    uint256 collateralChange,
    uint256 usdfChange,
    bool isCollateralIncrease,
    bool isDebtIncrease,
    address upperHint,
    address lowerHint
) external payable
```

**Flow**:
1. Get current trove state
2. Apply changes (add/remove collateral, borrow/repay)
3. Validate new collateral ratio
4. Update storage
5. Handle token transfers
6. Update SortedTroves position if needed
7. Emit TroveUpdated event

**Gas Optimizations**:
- Single storage read/write with PackedTrove
- Conditional token transfers (only if needed)
- Hint system to avoid O(n) list traversal

**Expected Gas**: <150,000 gas

---

### 4. claimCollateral()
**Purpose**: Claim excess collateral after liquidation

**Parameters**:
```solidity
function claimCollateral(address collateralAsset) external
```

**Flow**:
1. Check surplus collateral in LiquidityCore
2. Transfer to user
3. Update records
4. Emit CollateralClaimed event

**Expected Gas**: ~30,000 gas

---

## Gas Optimization Strategy

### 1. Use ALL Available Libraries ✅

```solidity
import {TransientStorage} from "../libraries/TransientStorage.sol";
import {PackedTrove} from "../libraries/PackedTrove.sol";
import {CalldataDecoder} from "../libraries/CalldataDecoder.sol";
import {BatchOperations} from "../libraries/BatchOperations.sol";
import {GasOptimizedMath} from "../libraries/GasOptimizedMath.sol";
```

### 2. Packed Calldata for openTrove()

**Instead of**:
```solidity
function openTrove(
    address collateralAsset,    // 32 bytes
    uint256 maxFeePercentage,   // 32 bytes
    uint256 collateralAmount,   // 32 bytes
    uint256 usdfAmount,         // 32 bytes
    address upperHint,          // 32 bytes
    address lowerHint           // 32 bytes
) // Total: 192 bytes calldata
```

**Use**:
```solidity
function openTrove(
    address collateralAsset,    // 20 bytes
    bytes32 packedParams,       // 32 bytes
    address upperHint,          // 20 bytes
    address lowerHint           // 20 bytes
) // Total: 92 bytes calldata
// Saves: ~1,600 gas

// Decode inside:
(uint16 maxFee, uint80 collateral, uint80 usdf) =
    CalldataDecoder.decodeOpenTroveParams(packedParams);
```

### 3. Single ICR Calculation with Transient Cache

```solidity
// Calculate once, store in transient storage
uint256 icr = _calculateICR(collateral, debt, price);
bytes32 ICR_CACHE = keccak256("icr.cache");
ICR_CACHE.tstore(icr);

// Later functions read from transient storage (100 gas vs 10,000 gas)
uint256 cachedIcr = ICR_CACHE.tload();
```

### 4. Batch Token Operations

**Instead of**:
```solidity
collateralToken.transferFrom(msg.sender, liquidityCore, amount);  // 21,000 gas
usdfToken.mint(msg.sender, usdfAmount);                          // 21,000 gas
usdfToken.mint(feeRecipient, feeAmount);                         // 21,000 gas
// Total: 63,000 gas
```

**Use**:
```solidity
BatchOperations.batchMint(
    usdfToken,
    [msg.sender, feeRecipient],
    [usdfAmount, feeAmount]
);
// Single external call: ~25,000 gas
// Saves: ~38,000 gas
```

### 5. PackedTrove Storage

```solidity
// Instead of multiple SSTOREs:
troves[user].debt = newDebt;           // 20,000 gas (cold)
troves[user].collateral = newColl;     // 20,000 gas
troves[user].stake = newStake;         // 20,000 gas
troves[user].status = Status.Active;   // 20,000 gas
// Total: 80,000 gas

// Use single packed write:
PackedTrove memory trove = PackedTrove({
    debt: uint128(newDebt),
    collateral: uint64(newColl / 1e10),  // Scaled
    lastUpdate: uint32(block.timestamp),
    status: uint16(Status.Active)
});
_setPackedTrove(user, trove);  // 20,000 gas (cold)
// Saves: 60,000 gas
```

---

## Testing Strategy (With Mocks)

### Mock Contracts Needed:

1. **MockPriceOracle.sol** ✅ (already exists)
```solidity
function getPrice(address asset) external view returns (uint256) {
    // Return fixed price for testing
    if (asset == WETH) return 2000e18;  // 1 ETH = $2000
    if (asset == WBTC) return 40000e18; // 1 BTC = $40,000
    return 1e18;  // Stablecoins = $1
}
```

2. **MockSortedTroves.sol** (create simple version)
```solidity
function insert(address id, uint256 icr, address hint1, address hint2) external {
    // Simple append - no sorting needed for basic tests
    list.push(id);
}

function remove(address id) external {
    // Simple removal
}
```

3. **MockUSDF.sol** (use existing MockERC20 with mint/burn)

### Test Structure:

```typescript
describe("BorrowerOperations - Gas Optimized", () => {
    let borrowerOps: BorrowerOperations;
    let liquidityCore: LiquidityCore;
    let mockOracle: MockPriceOracle;
    let mockSortedTroves: MockSortedTroves;
    let usdf: MockERC20;
    let weth: MockERC20;

    describe("openTrove", () => {
        it("Should open trove with <200k gas", async () => {
            const tx = await borrowerOps.openTrove(...);
            const receipt = await tx.wait();
            console.log("⛽ Gas used:", receipt.gasUsed);
            expect(receipt.gasUsed).to.be.lt(200000);
        });

        it("Should use packed calldata correctly", async () => {
            const packedParams = encodeOpenTroveParams(
                maxFee: 500,        // 0.5%
                collateral: 10e18,  // 10 ETH
                usdf: 15000e18      // 15,000 USDF
            );
            await borrowerOps.openTrove(WETH, packedParams, hint1, hint2);
        });

        it("Should validate minimum collateral ratio", async () => {
            // ICR must be >= 110%
            await expect(
                borrowerOps.openTrove(WETH, lowCollateralParams, ...)
            ).to.be.revertedWith("ICR below minimum");
        });
    });

    describe("closeTrove", () => {
        it("Should close trove with <80k gas", async () => {
            // First open
            await borrowerOps.openTrove(...);

            // Then close
            const tx = await borrowerOps.closeTrove(WETH);
            const receipt = await tx.wait();
            expect(receipt.gasUsed).to.be.lt(80000);
        });

        it("Should refund all collateral", async () => {
            const collateral = ethers.parseEther("10");
            await borrowerOps.openTrove(...);

            const balanceBefore = await weth.balanceOf(user);
            await borrowerOps.closeTrove(WETH);
            const balanceAfter = await weth.balanceOf(user);

            expect(balanceAfter - balanceBefore).to.equal(collateral);
        });
    });

    describe("adjustTrove", () => {
        it("Should adjust with <150k gas", async () => {
            await borrowerOps.openTrove(...);

            const tx = await borrowerOps.adjustTrove(
                WETH,
                500, // maxFee
                ethers.parseEther("5"), // add 5 ETH
                ethers.parseEther("5000"), // borrow 5k more
                true, // isCollateralIncrease
                true, // isDebtIncrease
                hint1,
                hint2
            );
            const receipt = await tx.wait();
            expect(receipt.gasUsed).to.be.lt(150000);
        });
    });

    describe("Gas Profiling", () => {
        it("Should profile all operations", async () => {
            console.log("\n⛽ GAS PROFILE:");

            // Open
            let tx = await borrowerOps.openTrove(...);
            let receipt = await tx.wait();
            console.log("  openTrove:", receipt.gasUsed);

            // Adjust (increase both)
            tx = await borrowerOps.adjustTrove(..., true, true, ...);
            receipt = await tx.wait();
            console.log("  adjustTrove (increase):", receipt.gasUsed);

            // Adjust (decrease both)
            tx = await borrowerOps.adjustTrove(..., false, false, ...);
            receipt = await tx.wait();
            console.log("  adjustTrove (decrease):", receipt.gasUsed);

            // Close
            tx = await borrowerOps.closeTrove(WETH);
            receipt = await tx.wait();
            console.log("  closeTrove:", receipt.gasUsed);
        });
    });
});
```

---

## Implementation Plan

### Step 1: Create Interface (15 min)
```solidity
// contracts/OrganisedSecured/interfaces/IBorrowerOperations.sol
interface IBorrowerOperations {
    function openTrove(...) external payable;
    function closeTrove(address asset) external;
    function adjustTrove(...) external payable;
    function claimCollateral(address asset) external;

    // View functions
    function getTrove(address user, address asset) external view returns (...);
    function getEntireDebtAndColl(address user, address asset) external view returns (...);
}
```

### Step 2: Create Mock Contracts (30 min)
- MockPriceOracle.sol (already exists, verify)
- MockSortedTroves.sol (simple version)

### Step 3: Implement BorrowerOperations (2 hours)
- Start with basic structure
- Add openTrove() with all optimizations
- Add closeTrove()
- Add adjustTrove()
- Add claimCollateral()

### Step 4: Write Tests (1 hour)
- 40+ test cases
- Gas profiling
- Edge cases
- Security tests

### Step 5: Optimize Further (30 min)
- Review gas profile
- Apply additional optimizations
- Achieve <200k gas target

---

## Storage Layout (Ultra-Optimized)

```solidity
contract BorrowerOperations is OptimizedSecurityBase {
    using TransientStorage for bytes32;
    using PackedTrove for bytes32;
    using CalldataDecoder for bytes32;
    using GasOptimizedMath for uint256;

    // Immutables (no storage cost after deployment)
    ILiquidityCore public immutable liquidityCore;
    IPriceOracle public immutable priceOracle;
    ISortedTroves public immutable sortedTroves;
    IERC20 public immutable usdfToken;

    // Transient storage slots (EIP-1153)
    bytes32 private constant ICR_CACHE = keccak256("icr.cache");
    bytes32 private constant PRICE_CACHE = keccak256("price.cache");

    // Packed trove storage (3 slots per trove)
    mapping(address => mapping(address => bytes32[3])) private _packedTroves;

    // Constants
    uint256 public constant MCR = 1100000000000000000; // 110%
    uint256 public constant CCR = 1500000000000000000; // 150%
    uint256 public constant BORROWING_FEE_FLOOR = 5e15; // 0.5%
}
```

---

## Key Decisions

### 1. Mock vs Real Oracle for Tests
**Decision**: Use MockPriceOracle for hardhat tests
**Reason**:
- Deterministic pricing
- No external dependencies
- Faster tests
- Real oracle for testnet only

### 2. Hints System
**Decision**: Require hints from frontend
**Reason**:
- Massive gas savings (25,000+ gas)
- Frontend can calculate hints off-chain
- User pays less gas

### 3. Packed Calldata
**Decision**: Use packed parameters for openTrove
**Reason**:
- 1,600 gas savings
- Acceptable UX tradeoff
- Frontend handles encoding

### 4. Fee Structure
**Decision**: Charge borrowing fee on debt issuance
**Reason**:
- Protocol revenue
- Standard practice
- 0.5% - 5% range based on utilization

---

## Success Criteria

### Functionality ✅
- [ ] openTrove works correctly
- [ ] closeTrove works correctly
- [ ] adjustTrove works correctly
- [ ] All validations in place
- [ ] 40+ tests passing

### Gas Efficiency ✅
- [ ] openTrove: <200k gas
- [ ] closeTrove: <80k gas
- [ ] adjustTrove: <150k gas
- [ ] All optimizations applied

### Code Quality ✅
- [ ] 100% test coverage
- [ ] No security vulnerabilities
- [ ] Well documented
- [ ] Clean, readable code

---

## After BorrowerOperations

Once BorrowerOperations is complete and tested:

1. **Deploy to testnet** with mock oracle
2. **Build real PriceOracle** with Chainlink
3. **Deploy to testnet** with real oracle
4. **Test with real price feeds**
5. **Move to TroveManager**

This approach lets you:
- ✅ Test core functionality immediately
- ✅ Validate gas optimizations
- ✅ Build PriceOracle when actually needed for deployment
- ✅ Parallel testing (hardhat + testnet)

---

## Estimated Timeline

**Total: 3-4 hours for fully optimized BorrowerOperations**

- Interface & Mocks: 45 min
- Implementation: 2 hours
- Testing: 1 hour
- Optimization & Polish: 30 min

**Ready to start?** Let me know and I'll begin implementing! 🚀

# Fluid Protocol Smart Contract Tutorial
*Your Complete Guide to Understanding Every Function*

## Table of Contents
1. [Protocol Overview](#protocol-overview)
2. [Lesson 1: Opening a Trove - `openTrove()`](#lesson-1-opening-a-trove)
3. [Lesson 2: Managing Collateral - `addColl()` & `withdrawColl()`](#lesson-2-managing-collateral)
4. [Lesson 3: Managing Debt - `withdrawUSDF()` & `repayUSDF()`](#lesson-3-managing-debt)
5. [Lesson 4: Advanced Operations - `adjustTrove()`](#lesson-4-advanced-operations)
6. [Lesson 5: Closing Positions - `closeTrove()`](#lesson-5-closing-positions)
7. [Lesson 6: Liquidation Process](#lesson-6-liquidation-process)
8. [Lesson 7: Stability Pool Operations](#lesson-7-stability-pool-operations)
9. [Contract Interactions Map](#contract-interactions-map)
10. [State Changes Summary](#state-changes-summary)

---

## Protocol Overview

Before diving into functions, understand the key concepts:

**Trove**: Your personal vault holding collateral and tracking your USDF debt
**USDF**: The stablecoin you mint (create) when you borrow
**ICR**: Individual Collateral Ratio = (Collateral Value in USD) / (Debt in USDF)
**Liquidation**: When your ICR falls below 110%, others can liquidate your trove

---

## Lesson 1: Opening a Trove - `openTrove()`

### Function Signature
```solidity
function openTrove(
    address asset,              // Collateral token (ETH = address(0))
    uint256 maxFeePercentage,   // Maximum fee you're willing to pay
    uint256 collAmount,         // Amount of collateral to deposit
    uint256 usdfAmount,         // Amount of USDF you want to mint
    address upperHint,          // Gas optimization hint
    address lowerHint           // Gas optimization hint
) external payable
```

### Step-by-Step Breakdown

#### Step 1: Input Validation (Lines 90-96)
```solidity
require(usdfAmount >= MIN_NET_DEBT, "Net debt too small");
require(troveManager.getTroveStatus(msg.sender, asset) == 0, "Trove already exists");
require(userTroveCount[msg.sender] < MAX_TROVES_PER_USER, "Too many troves per user");
```

**What happens:**
- System checks if you want to borrow at least 200 USDF (minimum)
- Verifies you don't already have a trove for this asset
- Ensures you don't exceed 10 troves per address limit

**State checked:**
- `MIN_NET_DEBT = 200e18` (200 USDF minimum)
- `userTroveCount[msg.sender]` - your current trove count
- `MAX_TROVES_PER_USER = 10`

#### Step 2: Price Validation (Line 96)
```solidity
_requireFreshPrice(asset);
```

**What happens:**
- System checks if the price oracle data is fresh (less than 1 hour old)
- Prevents using stale prices that could enable arbitrage

**State checked:**
- `priceOracle.getLastUpdateTime(asset)` vs current timestamp
- `MAX_PRICE_AGE = 3600` seconds (1 hour)

#### Step 3: Fee Calculation (Lines 98-101)
```solidity
uint256 borrowingFee = _getBorrowingFee(asset, usdfAmount);
require(borrowingFee <= usdfAmount.mulDiv(maxFeePercentage, DECIMAL_PRECISION), "Fee exceeds maximum");
```

**What happens:**
- Calculates borrowing fee based on base rate + floor rate
- Fee ranges from 0.5% to 5% of borrowed amount
- Protects you from paying more than your specified maximum

**Example:**
```
You want to borrow: 1000 USDF
Current base rate: 1%
Borrowing fee = max(0.5%, 0.5% + 1%) = 1.5%
Fee = 1000 * 1.5% = 15 USDF
```

#### Step 4: Debt Calculation (Lines 102-103)
```solidity
uint256 netDebt = usdfAmount + borrowingFee;
uint256 compositeDebt = netDebt + 200e18; // Gas compensation
```

**What happens:**
- Adds borrowing fee to your requested USDF amount
- Adds 200 USDF gas compensation (for potential liquidation)
- This gas compensation stays locked until you close the trove

**Example:**
```
Requested USDF: 1000
Borrowing fee: 15 USDF  
Gas compensation: 200 USDF
Total debt recorded: 1215 USDF
You receive: 1000 USDF
```

#### Step 5: Collateral Ratio Check (Lines 105-107)
```solidity
uint256 ICR = _getICR(asset, collAmount, compositeDebt);
require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");
```

**What happens:**
- Calculates your Individual Collateral Ratio
- Must be at least 135% (1.35e18)
- ICR = (collateral * price) / debt

**Example:**
```
Collateral: 2 ETH at $1500 = $3000
Total debt: 1215 USDF
ICR = $3000 / $1215 = 246.9% ✅ (above 135%)
```

#### Step 6: Collateral Transfer (Lines 109-114)
```solidity
if (asset == address(0)) {
    require(msg.value == collAmount, "Incorrect ETH amount");
} else {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), collAmount);
}
```

**What happens:**
- For ETH: Checks that msg.value matches collAmount
- For ERC20 tokens: Transfers from your wallet to contract
- Contract now holds your collateral

**Your wallet state:**
- ETH/Token balance decreases by collAmount
- You must have approved the contract (for ERC20s)

#### Step 7: Trove Creation (Lines 116-124)
```solidity
(uint256 debt, uint256 coll) = troveManager.updateTrove(
    msg.sender,
    asset,
    collAmount,
    true, // isCollIncrease
    compositeDebt,
    true  // isDebtIncrease
);
```

**What happens in TroveManager:**
- Creates new trove data structure
- Sets trove status to "active"
- Records your debt and collateral amounts
- Calculates your "stake" for liquidation rewards
- Updates global totals

**New state created:**
```solidity
troves[msg.sender][asset] = Trove({
    debt: 1215e18,           // Your total debt
    coll: 2e18,              // Your collateral (2 ETH)
    stake: calculatedStake,   // Your liquidation reward stake
    status: Status.active,    // Trove is now active
    L_CollateralSnapshot: 0,  // For reward tracking
    L_DebtSnapshot: 0        // For reward tracking
});
```

#### Step 8: USDF Minting (Line 127)
```solidity
usdfToken.mint(msg.sender, usdfAmount);
```

**What happens:**
- Protocol mints new USDF tokens to your address
- These are newly created tokens, not borrowed from a pool
- Your USDF balance increases

**Your wallet state:**
- USDF balance increases by 1000 USDF (in our example)
- Total USDF supply increases by 1000

#### Step 9: Fee Distribution (Lines 129-132)
```solidity
if (borrowingFee > 0) {
    usdfToken.mint(owner(), borrowingFee);
}
```

**What happens:**
- Protocol mints additional USDF equal to your borrowing fee
- These tokens go to the protocol owner as revenue
- Separate from the tokens you receive

#### Step 10: Gas Compensation (Line 135)
```solidity
usdfToken.mint(gasPool, 200e18);
```

**What happens:**
- Protocol mints 200 USDF to the gas pool
- This compensates future liquidators for gas costs
- These tokens are locked until trove closure

#### Step 11: Bookkeeping (Lines 137-140)
```solidity
userTroveCount[msg.sender]++;
emit TroveUpdated(msg.sender, asset, debt, coll, BorrowerOperation.openTrove);
```

**Final state changes:**
- Your trove count increases by 1
- Event emitted for frontend/indexing services
- All state is now consistent

### Complete Example: Alice Opens a Trove

**Initial State:**
- Alice has: 2 ETH ($1500 each = $3000 total)
- Alice wants: 1000 USDF
- ETH price: $1500 (fresh from oracle)
- Base borrowing rate: 1%

**Function Call:**
```solidity
BorrowerOperations.openTrove(
    address(0),      // ETH
    50000000000000000, // 5% max fee (in wei)
    2000000000000000000, // 2 ETH (in wei)  
    1000000000000000000000, // 1000 USDF (in wei)
    address(0),      // upperHint
    address(0)       // lowerHint
) { value: 2000000000000000000 } // Send 2 ETH
```

**Step-by-step execution:**

1. **Validation passes:**
   - 1000 USDF ≥ 200 USDF ✅
   - Alice has no existing ETH trove ✅
   - Alice has 0 troves < 10 limit ✅
   - Price is fresh ✅

2. **Fee calculation:**
   - Base rate: 1% + floor 0.5% = 1.5%
   - Borrowing fee: 1000 * 1.5% = 15 USDF ✅ (under 5% max)

3. **Debt calculation:**
   - Net debt: 1000 + 15 = 1015 USDF
   - Composite debt: 1015 + 200 = 1215 USDF

4. **ICR check:**
   - ICR: ($3000) / 1215 USDF = 246.9% ✅ (above 135%)

5. **Transfers:**
   - Alice's ETH balance: -2 ETH
   - Contract ETH balance: +2 ETH

6. **Trove creation:**
   - New trove created in TroveManager
   - Alice's stake calculated based on collateral
   - Global totals updated

7. **Token minting:**
   - Alice receives: 1000 USDF
   - Owner receives: 15 USDF (fee)
   - Gas pool receives: 200 USDF
   - Total new USDF: 1215 USDF

**Final State:**
- Alice: 1000 USDF, 0 ETH
- Alice's trove: 2 ETH collateral, 1215 USDF debt
- Protocol: 15 USDF revenue
- Gas pool: 200 USDF for liquidations
- Alice's trove count: 1

---

## Lesson 2: Managing Collateral - `addColl()` & `withdrawColl()`

### Adding Collateral - `addColl()`

#### Function Purpose
Add more collateral to your existing trove to improve your ICR and reduce liquidation risk.

#### Function Signature
```solidity
function addColl(
    address asset,
    uint256 collAmount,
    address upperHint,
    address lowerHint
) external payable
```

#### Step-by-Step Process

**Step 1: Validation (Lines 152-153)**
```solidity
require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
require(collAmount > 0, "Amount must be greater than 0");
```
- Checks you have an active trove for this asset
- Ensures you're adding a positive amount

**Step 2: Collateral Transfer (Lines 155-160)**
```solidity
if (asset == address(0)) {
    require(msg.value == collAmount, "Incorrect ETH amount");
} else {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), collAmount);
}
```
- Transfers additional collateral to the contract
- Same logic as openTrove for ETH vs ERC20

**Step 3: Trove Update (Lines 162-170)**
```solidity
(uint256 debt, uint256 coll) = troveManager.updateTrove(
    msg.sender,
    asset,
    collAmount,
    true, // isCollIncrease = true
    0,    // no debt change
    false // isDebtIncrease = false
);
```

**What happens in TroveManager:**
- Applies any pending liquidation rewards to your trove
- Increases your collateral amount
- Recalculates your stake (for liquidation rewards)
- Updates global collateral totals
- Updates your reward snapshots

**Example:**
```
Before: 2 ETH collateral, 1215 USDF debt, ICR = 246%
Add: 1 ETH ($1500)
After: 3 ETH collateral, 1215 USDF debt, ICR = 370%
Liquidation risk: Much lower ✅
```

### Withdrawing Collateral - `withdrawColl()`

#### Function Purpose
Remove collateral from your trove (as long as ICR stays above 135%).

#### Step-by-Step Process

**Step 1: Validation (Lines 184-185)**
```solidity
require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
require(collAmount > 0, "Amount must be greater than 0");
```

**Step 2: Trove Update (Lines 187-195)**
```solidity
(uint256 debt, uint256 coll) = troveManager.updateTrove(
    msg.sender,
    asset,
    collAmount,
    false, // isCollIncrease = false
    0,     // no debt change
    false  // isDebtIncrease = false  
);
```

**Step 3: ICR Safety Check (Lines 197-199)**
```solidity
uint256 ICR = _getICR(asset, coll, debt);
require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");
```
- Calculates ICR AFTER collateral withdrawal
- Must remain ≥ 135% or transaction reverts
- Protects you from accidentally making yourself liquidatable

**Step 4: Collateral Transfer (Lines 201-206)**
```solidity
if (asset == address(0)) {
    payable(msg.sender).transfer(collAmount);
} else {
    IERC20(asset).safeTransfer(msg.sender, collAmount);
}
```
- Transfers requested collateral back to your wallet

**Example - Safe Withdrawal:**
```
Before: 3 ETH ($1500 each), 1215 USDF debt
Withdraw: 0.5 ETH
After: 2.5 ETH ($3750), 1215 USDF debt
New ICR: $3750 / 1215 = 308% ✅ (above 135%)
```

**Example - Rejected Withdrawal:**
```
Before: 2 ETH ($1500 each), 1215 USDF debt, ICR = 246%
Try to withdraw: 1.5 ETH  
After calculation: 0.5 ETH ($750), 1215 USDF debt
New ICR: $750 / 1215 = 61% ❌ (below 135%)
Transaction reverts: "ICR below minimum"
```

---

## Lesson 3: Managing Debt - `withdrawUSDF()` & `repayUSDF()`

### Borrowing More USDF - `withdrawUSDF()`

#### Function Purpose
Mint additional USDF against your existing collateral (if ICR allows).

#### Function Signature
```solidity
function withdrawUSDF(
    address asset,
    uint256 maxFeePercentage,
    uint256 usdfAmount,
    address upperHint,
    address lowerHint
) external
```

#### Step-by-Step Process

**Step 1: Validation (Lines 221-222)**
```solidity
require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
require(usdfAmount > 0, "Amount must be greater than 0");
```

**Step 2: Fee Calculation (Lines 224-226)**
```solidity
uint256 borrowingFee = _getBorrowingFee(asset, usdfAmount);
require(borrowingFee <= usdfAmount.mulDiv(maxFeePercentage, DECIMAL_PRECISION), "Fee exceeds maximum");
```
- Same fee logic as openTrove()
- Protects against excessive fees

**Step 3: Trove Update (Lines 230-238)**
```solidity
uint256 netDebt = usdfAmount + borrowingFee;

(uint256 debt, uint256 coll) = troveManager.updateTrove(
    msg.sender,
    asset,
    0,      // no collateral change
    false,  // isCollIncrease = false
    netDebt,
    true    // isDebtIncrease = true
);
```

**Step 4: ICR Safety Check (Lines 240-242)**
```solidity
uint256 ICR = _getICR(asset, coll, debt);
require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");
```
- Ensures your ICR stays ≥ 135% after borrowing more

**Step 5: Token Minting & Fee Distribution (Lines 244-250)**
```solidity
usdfToken.mint(msg.sender, usdfAmount);

if (borrowingFee > 0) {
    usdfToken.mint(owner(), borrowingFee);
}
```

**Example:**
```
Current trove: 3 ETH ($4500), 1215 USDF debt, ICR = 370%
Borrow additional: 500 USDF
Fee (1.5%): 7.5 USDF
New debt: 1215 + 500 + 7.5 = 1722.5 USDF
New ICR: $4500 / 1722.5 = 261% ✅ (above 135%)
You receive: 500 USDF
```

### Repaying Debt - `repayUSDF()`

#### Function Purpose
Burn USDF tokens to reduce your debt and improve your ICR.

#### Step-by-Step Process

**Step 1: Validation (Lines 264-266)**
```solidity
require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
require(usdfAmount > 0, "Amount must be greater than 0");
require(usdfToken.balanceOf(msg.sender) >= usdfAmount, "Insufficient USDF balance");
```
- Ensures you have enough USDF to repay

**Step 2: Trove Update (Lines 268-276)**
```solidity
(uint256 debt, uint256 coll) = troveManager.updateTrove(
    msg.sender,
    asset,
    0,        // no collateral change
    false,    // isCollIncrease = false
    usdfAmount,
    false     // isDebtIncrease = false
);
```

**Step 3: Token Burning (Line 279)**
```solidity
usdfToken.burnFrom(msg.sender, usdfAmount);
```
- Burns your USDF tokens (removes them from existence)
- Reduces total USDF supply

**Example:**
```
Current trove: 3 ETH ($4500), 1722.5 USDF debt, ICR = 261%
Repay: 500 USDF
New debt: 1722.5 - 500 = 1222.5 USDF
New ICR: $4500 / 1222.5 = 368% ✅ (much safer)
Your USDF balance decreases by 500
```

---

## Lesson 4: Advanced Operations - `adjustTrove()`

### Function Purpose
Modify both collateral and debt in a single transaction - the Swiss Army knife of trove operations.

### Function Signature
```solidity
function adjustTrove(
    address asset,
    uint256 maxFeePercentage,
    uint256 collWithdrawal,     // Amount of collateral to withdraw (0 if adding)
    uint256 usdfChange,         // Amount of USDF to borrow/repay
    bool isDebtIncrease,        // true = borrow more, false = repay
    address upperHint,
    address lowerHint
) external payable
```

### Step-by-Step Process

**Step 1: Validation (Line 296)**
```solidity
require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");
```

**Step 2: Collateral Change Logic (Lines 298-309)**
```solidity
uint256 collChange = 0;
bool isCollIncrease = false;

// Handle collateral changes
if (msg.value > 0) {
    require(asset == address(0), "ETH sent for non-ETH asset");
    collChange = msg.value;
    isCollIncrease = true;
} else if (collWithdrawal > 0) {
    collChange = collWithdrawal;
    isCollIncrease = false;
}
```

**Logic:**
- If you send ETH with transaction → Adding ETH collateral
- If collWithdrawal > 0 → Withdrawing collateral
- If both are 0 → Only changing debt

**Step 3: Debt Change Logic (Lines 312-331)**
```solidity
uint256 netDebtChange = 0;
if (usdfChange > 0) {
    if (isDebtIncrease) {
        // Borrowing more USDF
        uint256 borrowingFee = _getBorrowingFee(asset, usdfChange);
        require(borrowingFee <= usdfChange.mulDiv(maxFeePercentage, DECIMAL_PRECISION), "Fee exceeds maximum");
        netDebtChange = usdfChange + borrowingFee;

        usdfToken.mint(msg.sender, usdfChange);
        if (borrowingFee > 0) {
            usdfToken.mint(owner(), borrowingFee);
        }
    } else {
        // Repaying USDF
        netDebtChange = usdfChange;
        usdfToken.burnFrom(msg.sender, usdfChange);
    }
}
```

**Step 4: Trove Update (Lines 333-341)**
```solidity
(uint256 debt, uint256 coll) = troveManager.updateTrove(
    msg.sender,
    asset,
    collChange,
    isCollIncrease,
    netDebtChange,
    isDebtIncrease
);
```

**Step 5: Final ICR Check (Lines 343-345)**
```solidity
uint256 ICR = _getICR(asset, coll, debt);
require(ICR >= MIN_COLLATERAL_RATIO, "ICR below minimum");
```

**Step 6: Collateral Transfer (Lines 347-354)**
```solidity
if (collWithdrawal > 0) {
    if (asset == address(0)) {
        payable(msg.sender).transfer(collWithdrawal);
    } else {
        IERC20(asset).safeTransfer(msg.sender, collWithdrawal);
    }
}
```

### Real-World Examples

**Example 1: Add collateral + Borrow more**
```solidity
// Current: 2 ETH, 1215 USDF debt
// Goal: Add 1 ETH, borrow 300 more USDF

adjustTrove(
    address(0),    // ETH
    50000000000000000, // 5% max fee
    0,             // No withdrawal
    300e18,        // Borrow 300 USDF
    true,          // isDebtIncrease = true
    address(0),
    address(0)
) { value: 1e18 } // Send 1 ETH

// Result: 3 ETH, ~1520 USDF debt (including fees)
// ICR improves from 246% to ~295%
```

**Example 2: Withdraw collateral + Repay debt**
```solidity
// Current: 3 ETH, 1520 USDF debt  
// Goal: Remove 0.5 ETH, repay 200 USDF

adjustTrove(
    address(0),    // ETH
    0,             // No borrowing fee
    0.5e18,        // Withdraw 0.5 ETH
    200e18,        // Repay 200 USDF
    false,         // isDebtIncrease = false
    address(0),
    address(0)
)

// Result: 2.5 ETH, 1320 USDF debt
// ICR changes from ~295% to ~284%
```

**Example 3: Leverage up (risky!)**
```solidity
// Current: 2 ETH ($3000), 1000 USDF debt
// Goal: Borrow max USDF to buy more ETH externally

// Max borrowable = ($3000 / 1.35) - 1000 = ~1222 - 1000 = 222 USDF
adjustTrove(
    address(0),
    50000000000000000,
    0,
    220e18,        // Borrow close to max
    true,
    address(0), 
    address(0)
)

// Result: 2 ETH, ~1225 USDF debt, ICR = ~245% (close to minimum)
// User can now buy more ETH with the 220 USDF (external to protocol)
```

---

## Lesson 5: Closing Positions - `closeTrove()`

### Function Purpose
Completely close your trove by repaying all debt and reclaiming all collateral.

### Function Signature
```solidity
function closeTrove(address asset) external
```

### Step-by-Step Process

**Step 1: Validation (Lines 363-366)**
```solidity
require(troveManager.getTroveStatus(msg.sender, asset) == 1, "Trove not active");

(uint256 debt, uint256 coll) = troveManager.getTroveDebtAndColl(msg.sender, asset);
require(debt > 200e18, "Cannot close trove with only gas compensation");
```
- Ensures you have an active trove
- Gets current debt and collateral (including any pending rewards)
- Prevents closing if only gas compensation remains

**Step 2: Debt Calculation (Lines 368-369)**
```solidity
uint256 netDebt = debt - 200e18; // Subtract gas compensation
require(usdfToken.balanceOf(msg.sender) >= netDebt, "Insufficient USDF balance");
```
- Calculates how much USDF you need to repay (excluding gas compensation)
- Gas compensation stays in the system and gets burned separately

**Step 3: Trove Closure (Lines 371-379)**
```solidity
troveManager.updateTrove(
    msg.sender,
    asset,
    coll,
    false, // isCollIncrease = false (removing all)
    debt,
    false  // isDebtIncrease = false (repaying all)
);
```

**What happens in TroveManager:**
- Applies any pending liquidation rewards first
- Sets trove status to "closedByOwner"
- Zeros out debt and collateral amounts
- Removes trove from sorted list (gas optimization)
- Updates global totals

**Step 4: Token Burning (Lines 381-385)**
```solidity
usdfToken.burnFrom(msg.sender, netDebt);
usdfToken.burnFrom(gasPool, 200e18);
```
- Burns your USDF to repay the debt
- Burns the gas compensation from gas pool
- Both reduce total USDF supply

**Step 5: Collateral Return (Lines 387-392)**
```solidity
if (asset == address(0)) {
    payable(msg.sender).transfer(coll);
} else {
    IERC20(asset).safeTransfer(msg.sender, coll);
}
```
- Returns ALL your collateral (including any liquidation rewards earned)

**Step 6: Bookkeeping (Lines 394-397)**
```solidity
userTroveCount[msg.sender]--;
emit TroveUpdated(msg.sender, asset, 0, 0, BorrowerOperation.closeTrove);
```

### Example: Alice Closes Her Trove

**Current State:**
- Alice's trove: 2.5 ETH, 1320 USDF debt
- Alice's wallet: 800 USDF
- She earned 0.1 ETH from liquidation rewards (now 2.6 ETH total)

**Problem:** Alice needs 1320 - 200 = 1120 USDF but only has 800 USDF.

**Options:**
1. Buy 320 more USDF from DEX/market
2. Partially repay debt first, then close later
3. Use `adjustTrove()` to withdraw some collateral, sell for USDF

**If Alice gets enough USDF:**
```solidity
// Alice now has 1120 USDF
closeTrove(address(0))

// Results:
// - Burns 1120 USDF from Alice
// - Burns 200 USDF from gas pool  
// - Alice receives 2.6 ETH
// - Alice's trove count: 0
// - Trove status: closed
```

**Final State:**
- Alice's wallet: 2.6 ETH, 0 USDF
- Protocol: 1320 USDF burned, 2.6 ETH transferred out
- Alice is completely out of the system

---

## Lesson 6: Liquidation Process

Understanding liquidations is crucial - they can happen to your troves or you can perform them on others.

### When Liquidation Occurs

**Trigger Condition:**
```solidity
ICR = (Collateral Value) / (Debt) < 110%
```

**Example:**
```
Your trove: 2 ETH, 1500 USDF debt
ETH price: $800 (dropped from $1500)
Current value: 2 × $800 = $1600
ICR = $1600 / $1500 = 106.7% < 110% ❌
→ Trove is liquidatable
```

### Liquidation Process - `liquidate()` Function

#### Function in TroveManager (Line 220)
```solidity
function liquidate(address borrower, address asset) external nonReentrant {
    _requireTroveIsActive(borrower, asset);
    
    address[] memory borrowers = new address[](1);
    borrowers[0] = borrower;
    batchLiquidateTroves(asset, borrowers);
}
```

### Step-by-Step Liquidation

**Step 1: Liquidation Detection**
- Anyone can call `liquidate(borrower, asset)`
- System checks if ICR < 110%
- Determines liquidation mode (Normal vs Recovery)

**Step 2: Recovery Mode Check**
```solidity
bool recoveryMode = _checkRecoveryMode(asset, price);
// Recovery mode = Total system ICR < 150%
```

**Step 3: Liquidation Calculation**
The system calculates what happens to the trove's debt and collateral:

**If Stability Pool has enough USDF:**
```
Debt to offset = min(trove debt, stability pool USDF)
Collateral to SP = (debt to offset / trove debt) × trove collateral
Gas compensation = 0.5% of collateral (to liquidator)
Surplus = remaining collateral (if ICR > 100%)
```

**If Stability Pool insufficient:**
```
Redistributed debt = debt not covered by SP
Redistributed collateral = collateral not taken by SP
→ Spread proportionally to all other troves
```

**Step 4: Execution**
1. **Stability Pool offset** (if applicable):
   - SP USDF burns debt
   - SP gets discounted collateral
   - SP depositors earn liquidation rewards

2. **Gas compensation**:
   - Liquidator gets 0.5% of collateral
   - Compensates for gas costs

3. **Redistribution** (if needed):
   - Remaining debt/collateral distributed to active troves
   - Based on their stake proportion

4. **Surplus handling**:
   - Any leftover collateral goes to CollSurplusPool
   - Original trove owner can claim it later

### Example Liquidation

**Initial State:**
- Bob's trove: 2 ETH ($800 each = $1600), 1500 USDF debt
- ICR: $1600 / $1500 = 106.7% < 110%
- Stability Pool: 10,000 USDF

**Liquidation Calculation:**
```
Total collateral: 2 ETH = $1600
Total debt: 1500 USDF
ICR: 106.7% (above 100%, so there's surplus)

Gas compensation: 2 ETH × 0.5% = 0.01 ETH
Collateral for SP: (1500/1500) × (2 - 0.01) = 1.99 ETH  
Debt offset by SP: 1500 USDF
Surplus: 0 ETH (all collateral used)
```

**Execution:**
1. Liquidator gets: 0.01 ETH (gas compensation)
2. Stability Pool: Burns 1500 USDF, gets 1.99 ETH
3. Bob's trove: Closed, status = liquidated
4. Bob: Loses everything (no surplus)

**With Surplus Example:**
If ETH was $900 instead of $800:
```
Total value: 2 ETH × $900 = $1800
ICR: $1800 / $1500 = 120% > 110% (not liquidatable)

But if liquidatable at $850:
Total value: $1700
Collateral for debt: 1500/850 = 1.76 ETH needed
Gas compensation: 0.01 ETH
Surplus: 2 - 1.76 - 0.01 = 0.23 ETH → goes to Bob
```

### Redistribution Mechanism

When Stability Pool can't absorb all debt:

**Example:**
- Bob's trove: 2 ETH, 1500 USDF debt (liquidatable)
- Stability Pool: Only 800 USDF available
- Other active troves: Alice (1 ETH, 500 USDF), Charlie (3 ETH, 1000 USDF)

**Calculation:**
```
SP offset: 800 USDF debt, 800/1500 × 2 ETH = 1.067 ETH
Remaining: 700 USDF debt, 0.933 ETH collateral
Gas compensation: 0.01 ETH (from SP portion)

Redistribution:
Alice stake: 1 ETH (40% of total 2.5 ETH)
Charlie stake: 1.5 ETH (60% of total 2.5 ETH)

Alice gets: 40% × 700 = 280 USDF debt, 40% × 0.933 = 0.373 ETH
Charlie gets: 60% × 700 = 420 USDF debt, 60% × 0.933 = 0.560 ETH
```

**Result:**
- Alice's trove: 1.373 ETH, 780 USDF debt
- Charlie's trove: 3.560 ETH, 1420 USDF debt  
- Both get more collateral than debt (they profit!)

---

## Lesson 7: Stability Pool Operations

The Stability Pool is where users deposit USDF to earn liquidation rewards and protect the system.

### Depositing to Stability Pool - `provideToSP()`

#### Function Purpose
Deposit USDF to earn liquidation rewards and FLUID governance tokens.

#### Function Signature
```solidity
function provideToSP(uint256 amount, address _frontEndTag) external
```

#### Step-by-Step Process

**Step 1: Validation (Lines 108-109)**
```solidity
require(amount > 0, "Amount must be greater than 0");
require(usdfToken.balanceOf(msg.sender) >= amount, "Insufficient USDF balance");
```

**Step 2: FLUID Issuance Trigger (Line 114)**
```solidity
_triggerFLUIDIssuance();
```
- Updates FLUID reward calculations
- Distributes FLUID tokens based on time elapsed

**Step 3: Existing Rewards Collection (Lines 117-126)**
```solidity
if (initialDeposit > 0) {
    uint256 fluidGain = _getFLUIDGain(msg.sender);
    if (fluidGain > 0) {
        fluidToken.transfer(msg.sender, fluidGain);
        emit FLUIDPaidToDepositor(msg.sender, fluidGain);
    }
}
_payOutCollateralGains(msg.sender);
```
- Pays out any accumulated FLUID rewards
- Pays out any accumulated collateral from liquidations

**Step 4: Deposit Update with Compounding (Lines 128-133)**
```solidity
uint256 compoundedUSDF = getCompoundedUSDF(msg.sender);
uint256 newDeposit = compoundedUSDF + amount;

deposits[msg.sender] = newDeposit;
totalUSDF = totalUSDF - compoundedUSDF + newDeposit;
```

**Key insight:** Your deposit compounds automatically based on liquidations!
- If liquidations occurred, your deposit might be less than original
- But you gained collateral to compensate
- New deposit = remaining USDF + new amount

**Step 5: Snapshot Update (Line 136)**
```solidity
_updateDepositSnapshots(msg.sender);
```
- Records current state for future reward calculations
- Tracks epoch, scale, and reward per unit values

**Step 6: USDF Transfer (Line 139)**
```solidity
IERC20(address(usdfToken)).safeTransferFrom(msg.sender, address(this), amount);
```

### Reward Mechanism Deep Dive

The Stability Pool uses a sophisticated **epoch/scale system** for precise reward tracking:

#### Epoch/Scale System
```solidity
uint256 public currentEpoch;  // Resets when pool is 100% depleted
uint256 public currentScale;  // Increases when P factor gets too small
uint256 public P = DECIMAL_PRECISION; // Product factor tracking pool depletion
```

**How it works:**
1. **P factor**: Starts at 1.0, decreases with each liquidation
2. **Scale**: Increases when P becomes very small (precision protection)
3. **Epoch**: Resets when pool is completely depleted

#### Reward Calculation Example

**Initial State:**
- Alice deposits: 10,000 USDF (50% of pool)
- Bob deposits: 10,000 USDF (50% of pool)
- Total pool: 20,000 USDF
- P factor: 1.0

**Liquidation 1:**
- Liquidated trove: 1000 USDF debt, 1.2 ETH collateral
- Pool absorbs: 1000 USDF debt
- Pool receives: 1.2 ETH
- New pool size: 19,000 USDF
- P factor: 19,000/20,000 = 0.95

**Alice's position after liquidation:**
```solidity
Alice's USDF = 10,000 × 0.95 = 9,500 USDF  
Alice's ETH gain = 10,000/20,000 × 1.2 ETH = 0.6 ETH

Net effect: Lost 500 USDF, gained 0.6 ETH worth ~$720
Net gain: $720 - $500 = $220 ✅
```

### Withdrawing from Stability Pool

#### Full Withdrawal - `withdrawAllFromSP()`
```solidity
function withdrawAllFromSP() external
```

**Process:**
1. Calculates your compounded deposit (after liquidations)
2. Pays out all FLUID rewards
3. Pays out all collateral gains
4. Returns remaining USDF
5. Resets your deposit to 0

#### Partial Withdrawal - `withdrawFromSP()`
```solidity
function withdrawFromSP(uint256 amount) external
```

**Process:**
1. Same as full withdrawal but only withdraws specified amount
2. Updates snapshots for remaining deposit
3. Maintains proportional rewards for remaining funds

### Complex Example: Multiple Liquidations

**Initial Setup:**
- Alice: 10,000 USDF (SP)
- Bob: 5,000 USDF (SP)  
- Total pool: 15,000 USDF
- P = 1.0, epoch = 0, scale = 0

**Liquidation 1:**
- Debt: 3,000 USDF, Collateral: 2.5 ETH
- New pool: 12,000 USDF  
- P = 12,000/15,000 = 0.8
- Alice's effective: 8,000 USDF + (10/15 × 2.5 = 1.67 ETH)
- Bob's effective: 4,000 USDF + (5/15 × 2.5 = 0.83 ETH)

**Liquidation 2:**
- Debt: 6,000 USDF, Collateral: 4 ETH
- New pool: 6,000 USDF
- P = 6,000/12,000 × 0.8 = 0.4
- Alice's effective: 4,000 USDF + prev ETH + (8/12 × 4 = 2.67 ETH)
- Total Alice: 4,000 USDF + 4.34 ETH

**If Alice withdraws all:**
- Receives: 4,000 USDF + 4.34 ETH
- Original: 10,000 USDF
- Net: Lost 6,000 USDF, gained 4.34 ETH ≈ $5,200
- Profit: ~$5,200 - $6,000 = -$800 (depends on ETH price)

But Alice also earned FLUID tokens worth potentially much more!

---

## Contract Interactions Map

### High-Level Architecture
```
User Interface Layer:
├── BorrowerOperations.sol (User actions)
└── EnhancedStabilityPool.sol (SP operations)
        ↓
Core Logic Layer:
├── TroveManager.sol (Trove state management)
├── PriceOracle.sol (Price feeds)
└── SortedTroves.sol (Gas optimization)
        ↓
Token Layer:
├── USDF.sol (Stablecoin)
└── FluidToken.sol (Governance)
        ↓
Pool Layer:
├── ActivePool.sol (Active collateral)
├── DefaultPool.sol (Redistributed funds)
└── CollSurplusPool.sol (Liquidation surplus)
```

### Function Call Flow: `openTrove()`

```
1. User calls BorrowerOperations.openTrove()
        ↓
2. BorrowerOperations validates inputs
        ↓  
3. BorrowerOperations.sol calls:
   - PriceOracle.getPrice() → Get current price
   - PriceOracle.getLastUpdateTime() → Check freshness
        ↓
4. BorrowerOperations calls TroveManager.updateTrove()
        ↓
5. TroveManager.sol:
   - Creates new Trove struct
   - Updates global totals (totalDebt, totalCollateral, totalStakes)
   - Calculates new stake
   - Updates reward snapshots
        ↓
6. BorrowerOperations calls USDF.mint() multiple times:
   - mint(user, usdfAmount) → User receives USDF
   - mint(owner, borrowingFee) → Protocol fee
   - mint(gasPool, 200e18) → Gas compensation
        ↓
7. Events emitted for frontend/monitoring
```

### Function Call Flow: Liquidation

```
1. Liquidator calls TroveManager.liquidate(borrower, asset)
        ↓
2. TroveManager checks ICR < 110%
        ↓
3. TroveManager calls StabilityPool.getTotalUSDF()
        ↓
4. TroveManager calculates liquidation amounts
        ↓
5. TroveManager calls StabilityPool.offset():
   - Burns USDF from pool
   - Adds collateral to pool
   - Updates epoch/scale/P factors
        ↓
6. TroveManager updates global state:
   - Removes trove from system
   - Updates totals
   - Handles redistribution if needed
        ↓
7. Transfer gas compensation to liquidator
```

---

## State Changes Summary

### Global State Variables

#### In TroveManager:
```solidity
mapping(address => mapping(address => Trove)) public troves;
// troves[user][asset] = Trove struct

mapping(address => uint256) public totalStakes;
// totalStakes[asset] = sum of all trove stakes for asset

mapping(address => uint256) public totalCollateral; 
// totalCollateral[asset] = total collateral held for asset

mapping(address => uint256) public totalDebt;
// totalDebt[asset] = total USDF debt for asset

mapping(address => uint256) public L_Collateral;
// L_Collateral[asset] = accumulated collateral rewards per unit staked

mapping(address => uint256) public L_Debt;
// L_Debt[asset] = accumulated debt rewards per unit staked
```

#### In BorrowerOperations:
```solidity
mapping(address => uint256) public userTroveCount;
// userTroveCount[user] = number of troves user has

mapping(address => uint256) public baseRate;
// baseRate[asset] = current borrowing fee base rate
```

#### In StabilityPool:
```solidity
uint256 public totalUSDF;
// Total USDF deposited in stability pool

mapping(address => uint256) public deposits;
// deposits[user] = user's USDF deposit amount

uint256 public P; 
// Product factor (starts at 1e18, decreases with liquidations)

uint256 public currentEpoch;
// Current epoch (resets when pool emptied)

uint256 public currentScale;
// Current scale (increases for precision)

mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public epochToScaleToSum;
// epochToScaleToSum[asset][epoch][scale] = reward sum for precise calculations
```

### State Changes by Function

#### `openTrove()`:
**Creates:**
- New Trove struct in `troves[user][asset]`
- Increments `userTroveCount[user]`

**Updates:**
- `totalStakes[asset] += newStake`
- `totalCollateral[asset] += collAmount`
- `totalDebt[asset] += compositeDebt`
- `USDF.totalSupply += (usdfAmount + borrowingFee + gasCompensation)`

**Transfers:**
- User collateral → BorrowerOperations contract
- Newly minted USDF → User wallet
- Borrowing fee → Protocol owner
- Gas compensation → Gas pool

#### `liquidate()`:
**Updates:**
- Sets `troves[borrower][asset].status = liquidated`
- Zeros out liquidated trove's debt and collateral
- `totalStakes[asset] -= liquidatedStake`
- `totalCollateral[asset] -= liquidatedColl`
- `totalDebt[asset] -= liquidatedDebt`

**In StabilityPool:**
- `totalUSDF -= debtOffset`
- `totalCollateral[asset] += collToSP`
- `P *= (1 - debtOffset/totalUSDF)` (simplified)
- Potentially updates `currentEpoch` or `currentScale`

**Redistributions (if applicable):**
- `L_Collateral[asset] += redistCollPerUnitStaked`
- `L_Debt[asset] += redistDebtPerUnitStaked`

**Transfers:**
- Gas compensation → Liquidator
- Collateral → Stability Pool
- Surplus collateral → CollSurplusPool

### Critical Invariants

The protocol maintains several mathematical invariants:

1. **Collateral Conservation:**
   ```
   Sum of all trove collateral + SP collateral + surplus collateral = 
   Total collateral ever deposited - Total collateral withdrawn
   ```

2. **USDF Supply Matching:**
   ```
   USDF total supply = 
   Sum of all trove debts + SP USDF + Outstanding gas compensations
   ```

3. **ICR Minimums:**
   ```
   All active troves: ICR ≥ 135%
   System in recovery mode if: Total ICR < 150%
   ```

4. **Stake Proportionality:**
   ```
   trove.stake / totalStakes[asset] = 
   trove.coll / totalCollateral[asset] (approximately)
   ```

5. **Reward Distribution:**
   ```
   Sum of all pending rewards = 
   Total liquidated amounts not yet claimed
   ```

This tutorial should give you a complete understanding of how every function works, what state changes occur, and how the contracts interact. Each function is a piece of the larger CDP system that enables decentralized stablecoin creation through over-collateralized positions.

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"id": "1", "content": "Create step-by-step tutorial for openTrove() function", "status": "completed"}, {"id": "2", "content": "Explain adjustTrove() and other trove management functions", "status": "completed"}, {"id": "3", "content": "Detail liquidation process and TroveManager interactions", "status": "completed"}, {"id": "4", "content": "Explain Stability Pool mechanics and reward distribution", "status": "completed"}, {"id": "5", "content": "Create comprehensive function interaction diagram", "status": "completed"}]
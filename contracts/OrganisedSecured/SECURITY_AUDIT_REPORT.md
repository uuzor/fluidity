# Security Audit Report - BorrowerOperationsV2, LiquidityCore, FluidAMM

**Date**: October 24, 2025
**Auditor**: Claude Code Analysis Agent
**Scope**: User borrow flow and liquidity management
**Severity Levels**: 🔴 CRITICAL | 🟠 HIGH | 🟡 MEDIUM | 🔵 LOW | ℹ️ INFO

---

## Executive Summary

Analyzed 3 core contracts for security vulnerabilities and logical bugs:
- **BorrowerOperationsV2.sol** (603 lines) - User borrowing interface
- **LiquidityCore.sol** (523 lines) - Centralized liquidity management
- **FluidAMM.sol** (861 lines) - DEX with protocol-owned liquidity

**Findings**: 12 issues identified (2 CRITICAL, 3 HIGH, 4 MEDIUM, 3 LOW)

---

## 🔴 CRITICAL ISSUES

### CRIT-1: Missing Balance Validation in LiquidityCore.transferCollateral()

**Location**: [LiquidityCore.sol:188-201](contracts/OrganisedSecured/core/LiquidityCore.sol#L188-L201)

**Description**:
The `transferCollateral()` function transfers ERC20 tokens without checking if the contract actually holds the tokens. This can cause silent failures or reverts.

**Vulnerable Code**:
```solidity
function transferCollateral(
    address asset,
    address to,
    uint256 amount
) external nonReentrant onlyAuthorized activeAsset(asset) validAmount(amount) {
    // ❌ NO CHECK: Does contract have enough balance?
    IERC20(asset).transfer(to, amount);  // Can fail if balance < amount
}
```

**Attack Scenario**:
1. BorrowerOperations calls `withdrawCollateral()` (updates accounting)
2. Then calls `transferCollateral()` to send tokens to user
3. If AMM emergency-withdrew some collateral in between, balance < amount
4. Transfer fails, but accounting already updated = accounting mismatch

**Impact**: Loss of collateral tracking integrity, users unable to withdraw funds

**Fix**:
```solidity
function transferCollateral(
    address asset,
    address to,
    uint256 amount
) external nonReentrant onlyAuthorized activeAsset(asset) validAmount(amount) {
    // ✅ Check balance before transfer
    uint256 balance = IERC20(asset).balanceOf(address(this));
    require(balance >= amount, "Insufficient contract balance");

    IERC20(asset).safeTransfer(to, amount);  // Use safeTransfer
}
```

**Status**: ❌ Not Fixed

---

### CRIT-2: Reentrancy Vulnerability in FluidAMM Emergency Withdrawal

**Location**: [FluidAMM.sol:716-765](contracts/OrganisedSecured/dex/FluidAMM.sol#L716-L765)

**Description**:
The `emergencyWithdrawLiquidity()` function has a reentrancy vulnerability because it:
1. Updates pool reserves
2. Transfers tokens **AFTER** the loop
3. No checks-effects-interactions pattern

**Vulnerable Code**:
```solidity
function emergencyWithdrawLiquidity(
    address token,
    uint256 amount,
    address destination
) external nonReentrant onlyValidRole(accessControl.EMERGENCY_ROLE()) {
    // Loop through pools and update reserves
    for (uint256 i = 0; i < _activePoolIds.length; i++) {
        // ... updates pool.reserve0/reserve1 ...
        amount -= withdrawn;  // ❌ Modifies amount during loop
    }

    // ❌ Transfer happens OUTSIDE the nonReentrant scope if called via delegate
    uint256 balance = IERC20(token).balanceOf(address(this));
    uint256 toTransfer = amount.min(balance);
    if (toTransfer > 0) {
        IERC20(token).safeTransfer(destination, toTransfer);  // External call
    }
}
```

**Attack Scenario**:
If destination is a malicious contract, it could call back into FluidAMM during transfer and manipulate state.

**Impact**: Pool reserve manipulation, fund drainage

**Fix**:
```solidity
function emergencyWithdrawLiquidity(
    address token,
    uint256 amount,
    address destination
) external nonReentrant onlyValidRole(accessControl.EMERGENCY_ROLE()) {
    require(amount > 0, "Invalid amount");
    require(destination != address(0), "Invalid destination");

    uint256 totalWithdrawn = 0;

    // ✅ Calculate total first
    for (uint256 i = 0; i < _activePoolIds.length; i++) {
        bytes32 poolId = _activePoolIds[i];
        Pool storage pool = _pools[poolId];

        if (!pool.isActive) continue;

        uint256 withdrawn = 0;
        uint256 remaining = amount - totalWithdrawn;

        if (remaining == 0) break;

        if (pool.token0 == token && pool.reserve0 > 0) {
            uint256 toWithdraw = remaining.min(pool.reserve0);
            pool.reserve0 = _toUint128(uint256(pool.reserve0) - toWithdraw);
            withdrawn += toWithdraw;
        }

        if (pool.token1 == token && pool.reserve1 > 0 && withdrawn < remaining) {
            uint256 toWithdraw = (remaining - withdrawn).min(pool.reserve1);
            pool.reserve1 = _toUint128(uint256(pool.reserve1) - toWithdraw);
            withdrawn += toWithdraw;
        }

        if (withdrawn > 0) {
            pool.lastUpdateTime = _toUint32(block.timestamp);
            totalWithdrawn += withdrawn;
            emit EmergencyWithdrawal(poolId, token, withdrawn, destination);
        }
    }

    // ✅ Transfer after all state updates
    if (totalWithdrawn > 0) {
        IERC20(token).safeTransfer(destination, totalWithdrawn);
    }
}
```

**Status**: ❌ Not Fixed

---

## 🟠 HIGH SEVERITY ISSUES

### HIGH-1: Integer Overflow in FluidAMM.addLiquidity() Liquidity Calculation

**Location**: [FluidAMM.sol:278-285](contracts/OrganisedSecured/dex/FluidAMM.sol#L278-L285)

**Description**:
Liquidity calculation has a logical error that could cause incorrect LP token minting.

**Vulnerable Code**:
```solidity
// Calculate liquidity
if (pool.totalSupply == 0) {
    liquidity = amount0.mul(amount1).sqrt() - MINIMUM_LIQUIDITY;
} else {
    // ❌ BUG: This formula is incorrect!
    liquidity = amount0.mul(pool.totalSupply).mulDiv(pool.totalSupply, reserve0).min(
        amount1.mul(pool.totalSupply).mulDiv(pool.totalSupply, reserve1)
    );
}
```

**Issue**:
The formula multiplies `pool.totalSupply` twice, which is wrong. Should be:
```solidity
liquidity = min(
    (amount0 * totalSupply) / reserve0,
    (amount1 * totalSupply) / reserve1
)
```

**Impact**: Incorrect LP token minting, potential economic exploit

**Fix**:
```solidity
if (pool.totalSupply == 0) {
    liquidity = amount0.mul(amount1).sqrt() - MINIMUM_LIQUIDITY;
} else {
    // ✅ Correct Uniswap V2 formula
    uint256 liquidity0 = amount0.mulDiv(pool.totalSupply, reserve0);
    uint256 liquidity1 = amount1.mulDiv(pool.totalSupply, reserve1);
    liquidity = liquidity0.min(liquidity1);
}
```

**Status**: ❌ Not Fixed

---

### HIGH-2: Missing Collateral Validation in BorrowerOperationsV2.closeTrove()

**Location**: [BorrowerOperationsV2.sol:246-281](contracts/OrganisedSecured/core/BorrowerOperationsV2.sol#L246-L281)

**Description**:
The `closeTrove()` function doesn't verify that LiquidityCore actually has the collateral before attempting withdrawal.

**Vulnerable Code**:
```solidity
function closeTrove(address asset) external override nonReentrant whenNotPaused {
    // Get trove data
    (uint256 debt, uint256 collateral) = troveManager.getTroveDebtAndColl(msg.sender, asset);

    // Burn USDF debt from user
    usdfToken.burnFrom(msg.sender, debt);

    // ❌ NO CHECK: Does LiquidityCore have the collateral?
    liquidityCore.burnDebt(asset, msg.sender, debt);
    liquidityCore.withdrawCollateral(asset, msg.sender, collateral);

    // ❌ This could fail if LiquidityCore doesn't have enough balance
    liquidityCore.transferCollateral(asset, msg.sender, collateral);

    // ... rest of function ...
}
```

**Attack Scenario**:
1. User has 10 ETH collateral in trove
2. LiquidityCore only has 5 ETH (rest in AMM)
3. User calls `closeTrove()`
4. Debt burns successfully
5. Transfer fails → user loses debt but doesn't get collateral back

**Impact**: User funds locked, loss of collateral

**Fix**:
```solidity
function closeTrove(address asset) external override nonReentrant whenNotPaused {
    _requireValidAsset(asset);

    if (!_isTroveActive[msg.sender][asset]) {
        revert TroveNotActive(msg.sender, asset);
    }

    // Get trove data
    (uint256 debt, uint256 collateral) = troveManager.getTroveDebtAndColl(msg.sender, asset);

    // ✅ CHECK: Ensure LiquidityCore has enough collateral
    uint256 availableCollateral = liquidityCore.getCollateralReserve(asset);
    if (availableCollateral < collateral) {
        // Try to recall collateral from AMM/Vaults
        uint256 shortage = collateral - availableCollateral;
        liquidityCore.borrowFromUnifiedPool(asset, shortage);
    }

    // Burn USDF debt from user
    usdfToken.burnFrom(msg.sender, debt);

    // Update LiquidityCore
    liquidityCore.burnDebt(asset, msg.sender, debt);
    liquidityCore.withdrawCollateral(asset, msg.sender, collateral);

    // Return collateral to user
    liquidityCore.transferCollateral(asset, msg.sender, collateral);

    // Close trove in TroveManager
    troveManager.closeTrove(msg.sender, asset);

    // Update local tracking
    _isTroveActive[msg.sender][asset] = false;
    _removeAssetFromUserList(msg.sender, asset);

    emit TroveClosed(msg.sender, asset);
}
```

**Status**: ❌ Not Fixed

---

### HIGH-3: Missing Debt Validation in BorrowerOperationsV2.openTrove()

**Location**: [BorrowerOperationsV2.sol:162-230](contracts/OrganisedSecured/core/BorrowerOperationsV2.sol#L162-L230)

**Description**:
The `openTrove()` function calculates `totalDebt` but never validates that the total debt is >= MIN_NET_DEBT + GAS_COMPENSATION.

**Vulnerable Code**:
```solidity
function openTrove(
    address asset,
    uint256 maxFeePercentage,
    uint256 collateralAmount,
    uint256 usdfAmount,
    address upperHint,
    address lowerHint
) external payable override nonReentrant whenNotPaused {
    // ... validation ...

    if (usdfAmount < MIN_NET_DEBT) {
        revert DebtBelowMinimum(usdfAmount, MIN_NET_DEBT);  // ✅ Checks USDF
    }

    // Fee Calculation
    vars.borrowingFee = _calculateBorrowingFee(asset, usdfAmount);
    vars.totalDebt = usdfAmount + vars.borrowingFee + GAS_COMPENSATION;

    // ❌ MISSING: Validate totalDebt >= MIN_NET_DEBT + GAS_COMPENSATION
    // If borrowingFee is very small, totalDebt could be < MIN_NET_DEBT + GAS_COMPENSATION

    // ... rest of function ...
}
```

**Impact**: Users could create dust troves with total debt below minimum threshold

**Fix**:
```solidity
// Fee Calculation
vars.borrowingFee = _calculateBorrowingFee(asset, usdfAmount);
vars.totalDebt = usdfAmount + vars.borrowingFee + GAS_COMPENSATION;

// ✅ Validate total debt including all fees
uint256 minimumTotalDebt = MIN_NET_DEBT + GAS_COMPENSATION;
if (vars.totalDebt < minimumTotalDebt) {
    revert DebtBelowMinimum(vars.totalDebt, minimumTotalDebt);
}
```

**Status**: ❌ Not Fixed

---

## 🟡 MEDIUM SEVERITY ISSUES

### MED-1: Race Condition in LiquidityCore Emergency Liquidity

**Location**: [LiquidityCore.sol:485-505](contracts/OrganisedSecured/core/LiquidityCore.sol#L485-L505)

**Description**:
Multiple emergency roles could call `provideEmergencyLiquidity()` simultaneously, causing accounting issues.

**Vulnerable Code**:
```solidity
function provideEmergencyLiquidity(
    address asset,
    uint256 amount
) external override nonReentrant onlyValidRole(accessControl.EMERGENCY_ROLE()) validAmount(amount) {
    AssetLiquidity storage liquidity = _assetLiquidity[asset];

    // ❌ NO LIMIT: Could overflow uint128 if too much emergency liquidity provided
    liquidity.collateralReserve = _toUint128(uint256(liquidity.collateralReserve) + amount);

    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    // ...
}
```

**Impact**: Potential uint128 overflow if excessive emergency liquidity provided

**Fix**:
```solidity
function provideEmergencyLiquidity(
    address asset,
    uint256 amount
) external override nonReentrant onlyValidRole(accessControl.EMERGENCY_ROLE()) validAmount(amount) {
    AssetLiquidity storage liquidity = _assetLiquidity[asset];

    // Transfer tokens first (checks-effects-interactions)
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

    // ✅ Add with overflow check
    uint256 newReserve = uint256(liquidity.collateralReserve) + amount;
    require(newReserve <= type(uint128).max, "Reserve overflow");

    liquidity.collateralReserve = _toUint128(newReserve);
    liquidity.lastUpdateTime = _toUint32(block.timestamp);

    emit EmergencyLiquidityProvided(asset, amount, msg.sender);
}
```

**Status**: ❌ Not Fixed

---

### MED-2: Missing K-Invariant Check in FluidAMM.removeLiquidity()

**Location**: [FluidAMM.sol:305-355](contracts/OrganisedSecured/dex/FluidAMM.sol#L305-L355)

**Description**:
The `removeLiquidity()` function updates reserves and k but doesn't verify the constant product is maintained.

**Vulnerable Code**:
```solidity
function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin
) external override nonReentrant whenNotPaused onlyValidRole(accessControl.ADMIN_ROLE())
    returns (uint256 amountA, uint256 amountB) {
    // ... calculate amounts ...

    // Update pool
    pool.reserve0 = _toUint128(uint256(pool.reserve0) - amount0);
    pool.reserve1 = _toUint128(uint256(pool.reserve1) - amount1);
    pool.totalSupply -= liquidity;
    pool.kLast = uint256(pool.reserve0).mul(pool.reserve1);  // ✅ Updates k

    // ❌ NO VERIFICATION: Should verify k is still valid (k >= kMin or something)

    IERC20(token0).safeTransfer(msg.sender, amount0);
    IERC20(token1).safeTransfer(msg.sender, amount1);
    // ...
}
```

**Impact**: Potential pool imbalance if liquidity removal breaks constant product

**Fix**: Add k verification or minimum k threshold check

**Status**: ❌ Not Fixed

---

### MED-3: Incomplete Price Validation in FluidAMM._validatePrice()

**Location**: [FluidAMM.sol:553-605](contracts/OrganisedSecured/dex/FluidAMM.sol#L553-L605)

**Description**:
Price validation logic has edge cases where it might not validate properly.

**Vulnerable Code**:
```solidity
function _validatePrice(
    bytes32 poolId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut
) private view {
    Pool storage pool = _pools[poolId];

    // Skip validation if pool doesn't require it
    if (!pool.requireOracleValidation) {
        return;
    }

    // ... get prices ...

    // ❌ ISSUE: ammPrice calculation doesn't account for decimals
    uint256 ammPrice = amountOut.mulDiv(priceIn, amountIn);
    uint256 oraclePrice = priceOut;

    // What if tokens have different decimals? (USDC=6, WETH=18)
}
```

**Impact**: Price validation could pass for manipulated swaps if token decimals differ

**Fix**: Normalize prices based on token decimals before comparing

**Status**: ❌ Not Fixed

---

### MED-4: Front-Running Vulnerability in BorrowerOperationsV2.adjustTrove()

**Location**: [BorrowerOperationsV2.sol:288-373](contracts/OrganisedSecured/core/BorrowerOperationsV2.sol#L288-L373)

**Description**:
The `adjustTrove()` function uses hints for sorted list insertion, which can be front-run.

**Vulnerable Code**:
```solidity
function adjustTrove(
    address asset,
    uint256 maxFeePercentage,
    uint256 collateralChange,
    uint256 debtChange,
    bool isCollateralIncrease,
    bool isDebtIncrease,
    address upperHint,
    address lowerHint  // ❌ These hints can become stale if front-run
) external payable override nonReentrant whenNotPaused {
    // ... operations ...

    // ❌ If another tx changes the sorted list before this, hints are wrong
    sortedTroves.reInsert(vars.asset, msg.sender, vars.newNominalICR, upperHint, lowerHint);
}
```

**Impact**: Transaction reverts if front-run, poor UX

**Fix**: Add hint staleness tolerance or allow missing hints (full traversal fallback)

**Status**: ⚠️ Partial (requires SortedTroves modification)

---

## 🔵 LOW SEVERITY ISSUES

### LOW-1: Unused Variable in FluidAMM.swapExactTokensForTokens()

**Location**: [FluidAMM.sol:421-430](contracts/OrganisedSecured/dex/FluidAMM.sol#L421-L430)

**Description**:
K-invariant verification uses actual balances but doesn't account for protocol fees already collected.

**Impact**: Minor gas inefficiency, no security risk

**Status**: ℹ️ Info

---

### LOW-2: Missing Event in BorrowerOperationsV2.setTroveManager()

**Location**: [BorrowerOperationsV2.sol:584-588](contracts/OrganisedSecured/core/BorrowerOperationsV2.sol#L584-L588)

**Description**:
Critical admin function doesn't emit an event.

**Fix**:
```solidity
event TroveManagerSet(address indexed troveManager);

function setTroveManager(address _troveManager) external onlyValidRole(accessControl.ADMIN_ROLE()) {
    require(_troveManager != address(0), "BO: Invalid TroveManager");
    require(address(troveManager) == address(0), "BO: TroveManager already set");
    troveManager = ITroveManager(_troveManager);

    // ✅ Add event
    emit TroveManagerSet(_troveManager);
}
```

**Status**: ❌ Not Fixed

---

### LOW-3: Gas Inefficiency in LiquidityCore.getActiveAssets()

**Location**: [LiquidityCore.sol:461-481](contracts/OrganisedSecured/core/LiquidityCore.sol#L461-L481)

**Description**:
Function loops through array twice (once to count, once to populate).

**Fix**: Use dynamic array or caching

**Status**: ℹ️ Info

---

## ℹ️ CODE QUALITY ISSUES

### INFO-1: Inconsistent Error Handling

**Description**: Some functions use `require()`, others use custom errors. Recommend standardizing on custom errors for gas efficiency.

### INFO-2: Missing NatSpec Comments

**Description**: Several internal functions lack comprehensive NatSpec documentation.

### INFO-3: Magic Numbers

**Description**: Several hardcoded values (1000, 10000, etc.) should be constants with descriptive names.

---

## 📊 Summary Table

| ID | Severity | Contract | Function | Issue | Status |
|----|----------|----------|----------|-------|--------|
| CRIT-1 | 🔴 CRITICAL | LiquidityCore | transferCollateral | Missing balance check | ❌ Not Fixed |
| CRIT-2 | 🔴 CRITICAL | FluidAMM | emergencyWithdrawLiquidity | Reentrancy risk | ❌ Not Fixed |
| HIGH-1 | 🟠 HIGH | FluidAMM | addLiquidity | Wrong LP calculation | ❌ Not Fixed |
| HIGH-2 | 🟠 HIGH | BorrowerOperationsV2 | closeTrove | Missing collateral check | ❌ Not Fixed |
| HIGH-3 | 🟠 HIGH | BorrowerOperationsV2 | openTrove | Missing debt validation | ❌ Not Fixed |
| MED-1 | 🟡 MEDIUM | LiquidityCore | provideEmergencyLiquidity | Overflow risk | ❌ Not Fixed |
| MED-2 | 🟡 MEDIUM | FluidAMM | removeLiquidity | Missing k-check | ❌ Not Fixed |
| MED-3 | 🟡 MEDIUM | FluidAMM | _validatePrice | Decimal handling | ❌ Not Fixed |
| MED-4 | 🟡 MEDIUM | BorrowerOperationsV2 | adjustTrove | Front-running | ⚠️ Partial |
| LOW-1 | 🔵 LOW | FluidAMM | swapExactTokensForTokens | Unused variable | ℹ️ Info |
| LOW-2 | 🔵 LOW | BorrowerOperationsV2 | setTroveManager | Missing event | ❌ Not Fixed |
| LOW-3 | 🔵 LOW | LiquidityCore | getActiveAssets | Gas inefficiency | ℹ️ Info |

---

## 🎯 Recommended Actions

### Immediate (Before Mainnet)
1. **Fix CRIT-1 & CRIT-2** - Add balance checks and fix reentrancy
2. **Fix HIGH-1, HIGH-2, HIGH-3** - Correct formulas and validations
3. **Comprehensive testing** - Add edge case tests for all findings
4. **Professional audit** - Engage third-party security firm

### Short-term
1. Fix all MEDIUM severity issues
2. Add comprehensive NatSpec documentation
3. Implement circuit breakers for emergency scenarios

### Long-term
1. Implement automated monitoring for accounting discrepancies
2. Add comprehensive event emissions for off-chain tracking
3. Gas optimization review

---

## 📝 Test Coverage Recommendations

Add tests for:
1. **LiquidityCore**: Insufficient balance scenarios
2. **BorrowerOperations**: Edge cases with fees and minimum debt
3. **FluidAMM**: LP token calculation accuracy, price oracle edge cases
4. **Integration**: Full user flow with AMM capital allocation

---

**Conclusion**: The codebase shows good architecture and gas optimization practices, but has several critical issues that MUST be fixed before production deployment. The integration between LiquidityCore and external contracts (AMM, UnifiedPool) needs additional safeguards.

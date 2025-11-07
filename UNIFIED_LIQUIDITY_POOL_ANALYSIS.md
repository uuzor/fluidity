# UnifiedLiquidityPool.sol - Complete Analysis

## Overview
**Location:** `contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol`

The **UnifiedLiquidityPool** is the central hub for **cross-protocol liquidity management** in Fluid Protocol. It serves as a unified lending/borrowing marketplace that is **completely separate from the CDP system** (BorrowerOperationsV2/TroveManagerV2).

---

## Core Purpose

### What It Does
1. **Unified Lending Marketplace** - Users deposit tokens to earn yield
2. **Lending/Borrowing Facility** - Users borrow against deposits as collateral
3. **Liquidity Allocation** - Distributes liquidity across protocol components (AMM, vaults, staking)
4. **Rate Management** - Dynamic borrow/supply rates based on utilization
5. **Health Factor & Liquidation** - Monitors collateral positions and enables liquidations

### Key Distinction from CDP System
| Feature | UnifiedLiquidityPool | CDP System (TroveManager) |
|---------|----------------------|--------------------------|
| **Primary Asset** | Any ERC20 token | USDF stablecoin only |
| **Collateral** | Whitelisted assets | WETH, WBTC |
| **Purpose** | Lending marketplace | Stablecoin creation |
| **Interest Rates** | Dynamic (aave-like) | Fixed mint fee |
| **User Type** | Lenders & borrowers | CDP owners |
| **Integration** | Separate system | Core CDP mechanism |

---

## Data Structures

### 1. **AssetInfo** - Asset Configuration
```solidity
struct AssetInfo {
    address token;                  // Token address
    uint256 totalDeposits;         // Total supplied amount
    uint256 totalBorrows;          // Total borrowed amount
    uint256 reserveFactor;         // Reserve factor (% to protocol)
    uint256 collateralFactor;      // Collateral value factor (0-1e18)
    uint256 liquidationThreshold;  // LT before liquidation
    uint256 liquidationBonus;      // Liquidator bonus (5-10%)
    bool isActive;                 // Can be used?
    bool canBorrow;                // Can be borrowed?
    bool canCollateralize;         // Can be used as collateral?
}
```

**Example Configuration:**
```
WETH as collateral:
- collateralFactor: 0.8e18 (80% of value counts)
- liquidationThreshold: 0.85e18 (liquidate at 85% LT)
- liquidationBonus: 1.05e18 (5% bonus for liquidator)

USDF as borrow asset:
- canBorrow: true
- totalBorrows: tracked across users
```

### 2. **LiquidityAllocation** - Capital Distribution
```solidity
struct LiquidityAllocation {
    uint256 lendingPool;       // % kept for lender withdrawals
    uint256 dexPool;           // % allocated to FluidAMM (40%)
    uint256 vaultStrategies;   // % allocated to yield vaults (20%)
    uint256 liquidStaking;     // % allocated to staking (10%)
    uint256 reserves;          // % kept as protocol reserve (30%)
}
```

**Total = 100% of deposited liquidity**

---

## Core Functions

### 1. Deposit/Withdraw (Lending Side)
```solidity
function deposit(address token, uint256 amount) external returns (uint256 shares)
- User deposits ERC20 token
- Earns yield based on supply rate
- Returns share amount (1:1 for simplicity)
- Emits: LiquidityDeposited

function withdraw(address token, uint256 shares) external returns (uint256 amount)
- Withdraw deposited amount + earned yield
- Requires available liquidity
- Emits: LiquidityWithdrawn
```

### 2. Borrow/Repay (Borrowing Side)
```solidity
function borrow(address token, uint256 amount, address collateralToken) external
- User borrows token using collateral
- Checks health factor: collateralValue >= borrowAmount
- Collateral check: collateralAmount * collateralFactor >= totalBorrows
- Charges borrow interest (accumulated implicitly)
- Emits: LiquidityBorrowed

function repay(address token, uint256 amount) external
- Repay borrowed amount + accrued interest
- Requires user to have borrowed balance
- Emits: LiquidityRepaid
```

### 3. Rate Calculations (Key for Frontend)
```solidity
function getUtilizationRate(address token) public view returns (uint256)
- utilRate = totalBorrows * 1e18 / totalDeposits
- Range: 0 to 1e18 (0% to 100%)

function getBorrowRate(address token) public view returns (uint256)
- Dynamic rate based on utilization
- Formula (Two-slope):
  * Base: 2%
  * Slope 1: 8% (up to 80% utilization)
  * Slope 2: 50% (above 80% utilization)

- Example rates:
  * 0% utilization → 2% APY
  * 50% utilization → 7% APY
  * 80% utilization → 10% APY
  * 100% utilization → 72.5% APY

function getSupplyRate(address token) external view returns (uint256)
- supplyRate = borrowRate * utilizationRate * 0.9
- (90% after 10% reserve factor)
```

### 4. Health Factor & Liquidation
```solidity
function getUserHealthFactor(address user) external view returns (uint256)
- healthFactor = totalCollateralValue / totalDebtValue
- Calculation:
  * For each asset: collateral = deposits * collateralFactor
  * For each asset: debt = borrows (in same value terms)
  * healthFactor = totalCollateral / totalDebt
- Safe if > 1.0e18 (100%)
- Liquidatable if < 1.0e18

function isLiquidatable(address user) external view returns (bool)
- Returns true if healthFactor < 1.0

function liquidate(address user, address collateralToken, address debtToken, uint256 debtAmount)
- Liquidator pays off user's debt
- Receives user's collateral + 5% bonus
- User's health factor improves
```

### 5. Admin Management
```solidity
function addAsset(address token, AssetInfo calldata assetInfo) external onlyAdmin
- Configure new token support
- Sets all parameters (factors, rates, limits)

function updateAsset(address token, AssetInfo calldata assetInfo) external onlyAdmin
- Update asset configuration
- Can enable/disable borrowing, collateral

function allocateLiquidity(address token, LiquidityAllocation calldata allocation) external onlyAdmin
- Set distribution percentages
- Rebalancing triggers withdrawal from strategies
```

---

## Integration Points

### Connected Contracts

#### 1. **LiquidityCore** (CDP System Integration)
```solidity
// LiquidityCore.sol
IUnifiedLiquidityPool public immutable unifiedPool;

// Can request liquidity from unified pool
function requestLiquidity(address token, uint256 amount) external
function returnLiquidity(address token, uint256 amount) external
```
**Purpose:** Cross-protocol liquidity sharing between CDP and lending

#### 2. **FluidAMM** (DEX Integration)
```solidity
// FluidAMM.sol
IUnifiedLiquidityPool public immutable unifiedPool;

// Gets 40% of deposits via borrowLiquidity hooks
function borrowLiquidity(address token, uint256 amount) external
function returnLiquidity(address token, uint256 amount) external
```
**Purpose:** AMM uses unified pool liquidity for swaps

#### 3. **OptimizedSecurityBase** (Access Control)
```solidity
// Uses EIP-1153 transient storage for reentrancy protection
// Saves ~19,800 gas per transaction
onlyValidRole(accessControl.ADMIN_ROLE())
```

---

## Frontend Integration Guide

### What Frontend Should Display

#### 1. **Lending Dashboard**
```javascript
// For each supported asset:
const assetInfo = await unifiedPool.getAssetInfo(tokenAddress);

Display:
- Token name/symbol/logo
- Total deposits: assetInfo.totalDeposits
- Total borrows: assetInfo.totalBorrows
- Utilization: (borrows / deposits) * 100%
- Supply APY: getSupplyRate(token) / 1e18 * 100
- Borrow APY: getBorrowRate(token) / 1e18 * 100
- Available liquidity: getTotalLiquidity(token) - totalBorrows
```

#### 2. **User Positions**
```javascript
// Get user's position in unified pool:
const deposits = await unifiedPool.getUserDeposits(userAddress, tokenAddress);
const borrows = await unifiedPool.getUserBorrows(userAddress, tokenAddress);
const healthFactor = await unifiedPool.getUserHealthFactor(userAddress);
const canLiquidate = await unifiedPool.isLiquidatable(userAddress);

Display:
- My Deposits: deposits (with earned yield)
- My Borrows: borrows (with accrued interest)
- Health Factor: healthFactor / 1e18
  * > 1.0 = SAFE (green)
  * 0.5-1.0 = WARNING (yellow)
  * < 0.5 = CRITICAL (red)
- Liquidation status
```

#### 3. **Borrow/Deposit Forms**
```javascript
// When user enters borrow amount:
function validateBorrow(token, amount, collateralToken, collateralAmount) {
  const collateralFactor = assetInfo[collateralToken].collateralFactor;
  const collateralValue = collateralAmount * collateralFactor / 1e18;
  const totalBorrows = await unifiedPool.getUserBorrows(user, token) + amount;

  // Check: collateralValue >= totalBorrows
  if (collateralValue < totalBorrows) {
    return "Insufficient collateral";
  }

  // Also check health factor after borrow
  const newHealthFactor = await unifiedPool.getUserHealthFactor(user);
  if (newHealthFactor < 1.2e18) {
    return "Borrow would reduce health factor";
  }

  return "OK to borrow";
}
```

#### 4. **Rate Display**
```javascript
// Real-time rate updates:
async function displayRates(tokenAddress) {
  const utilizationRate = await unifiedPool.getUtilizationRate(tokenAddress);
  const borrowRate = await unifiedPool.getBorrowRate(tokenAddress);
  const supplyRate = await unifiedPool.getSupplyRate(tokenAddress);

  return {
    utilization: `${(utilizationRate / 1e16).toFixed(2)}%`,
    borrowAPY: `${(borrowRate / 1e16).toFixed(2)}%`,
    supplyAPY: `${(supplyRate / 1e16).toFixed(2)}%`
  };
}
```

---

## Key Features for Frontend

### 1. **Asset Support Display**
```javascript
const supportedAssets = await unifiedPool.getSupportedAssets();
// Frontend filters based on:
// - isActive: show in UI
// - canBorrow: enable borrow button
// - canCollateralize: enable as collateral selection
```

### 2. **Yield Opportunities**
- **Lenders earn:** Supply APY from borrowing fees
- **Example:** Deposit 100 USDF → earn 5% APY → annual gain = 5 USDF
- **Rate varies** with utilization (higher when more borrowed)

### 3. **Risk Indicators**
```javascript
function getRiskLevel(healthFactor) {
  const hf = healthFactor / 1e18;
  if (hf > 2.0) return "SAFE";           // Green
  if (hf > 1.5) return "OPTIMAL";        // Light Green
  if (hf > 1.0) return "CAUTION";        // Yellow
  if (hf > 0.8) return "HIGH RISK";      // Orange
  return "CRITICAL";                      // Red - Liquidatable
}
```

### 4. **Liquidation Information**
```javascript
// Show liquidator incentive:
function getLiquidationIncentive(debtAmount, assetInfo) {
  const bonus = assetInfo.liquidationBonus / 1e18;
  const liquidatorReceives = debtAmount * bonus;
  return liquidatorReceives;
}
// Display: "Liquidators get 5% bonus"
```

---

## Differences from CDP System

### UnifiedLiquidityPool (This Contract)
✅ **Separate lending marketplace**
✅ Any ERC20 token can be lent/borrowed
✅ Dynamic interest rates (aave-style)
✅ Supply side yield for depositors
✅ Independent health factor system
✅ No minting of tokens (just lending)

### CDP System (TroveManager)
✅ Creates USDF stablecoin
✅ Only WETH/WBTC as collateral
✅ Fixed redemption fee (~0.5%)
✅ No lender interest (protocol keeps fees)
✅ CR (Collateral Ratio) instead of health factor
✅ Mints new USDF tokens

### Cross-Protocol Liquidity
- Both systems can request liquidity from each other
- UnifiedLiquidityPool stores backup liquidity
- If CDP needs more liquidity → request from unified pool
- If unified pool needs rebalancing → deploy to strategies

---

## Implementation Checklist for Frontend

### Phase 1: Read-Only Display
- [ ] List supported assets with their parameters
- [ ] Display utilization rates and APYs
- [ ] Show user's lending positions
- [ ] Show user's borrowing positions
- [ ] Display health factor with color coding

### Phase 2: User Actions
- [ ] Deposit form with amount validation
- [ ] Withdraw form with liquidity check
- [ ] Borrow form with collateral validation
- [ ] Repay form with balance check

### Phase 3: Risk Management
- [ ] Real-time health factor updates
- [ ] Liquidation warnings
- [ ] Rate impact calculator
- [ ] Portfolio overview (total deposits/borrows across all assets)

### Phase 4: Advanced Features
- [ ] Supply/borrow rate charts
- [ ] Historical yield tracking
- [ ] Liquidation opportunities dashboard
- [ ] Multi-asset position management

---

## Gas Optimization

**EIP-1153 Transient Storage:**
- Uses `tstore`/`tload` for reentrancy checks
- Saves ~19,800 gas per transaction vs storage-based protection
- Solves the "storage tax" issue of traditional guards

---

## Test Coverage Needed

1. ✅ Deposit/withdraw basic flow
2. ✅ Borrow/repay with collateral
3. ✅ Rate calculation accuracy
4. ✅ Health factor computation
5. ✅ Liquidation mechanics
6. ⚠️ Multi-asset portfolio health
7. ⚠️ Interest accrual (not implemented yet)
8. ⚠️ Yield distribution to staking/vaults

---

## TODO Items

1. **Interest Accrual** - Currently implicit, needs explicit tracking
2. **Yield Distribution** - Allocate to strategies based on percentages
3. **Price Oracle Integration** - Remove hardcoded 2000:1 WETH:USDF ratio
4. **Risk Management** - Add maximum LTV, isolation mode for new assets
5. **Events** - Add LiquidityBorrowed, LiquidityRepaid events

---

## Summary for Frontend Team

**UnifiedLiquidityPool is the lending/borrowing protocol separate from CDPs.**

It allows:
- **Lenders:** Deposit tokens → earn supply APY
- **Borrowers:** Borrow tokens → pay borrow APY (using collateral)
- **Liquidators:** Profit from unhealthy positions

**For MVP Frontend, focus on:**
1. Asset list with rates
2. User deposit/borrow positions
3. Health factor monitoring
4. Borrow/deposit/repay forms

**Key Difference:** This is aave-like, CDP system is maker-like. Both work together for full protocol coverage.

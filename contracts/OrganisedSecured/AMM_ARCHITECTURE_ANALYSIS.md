# FluidAMM Architecture Analysis - Integration with V2

## 🎯 Executive Summary

The FluidAMM will integrate seamlessly with your existing V2 architecture to create a **unified liquidity layer** where idle collateral becomes productive capital. This analysis maps out all integration points, data flows, and architectural decisions.

---

## 🏗️ Current V2 Architecture (What We Have)

```
┌────────────────────────────────────────────────────────────────┐
│                    CURRENT V2 STACK                             │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  User → BorrowerOperationsV2 ────────┐                         │
│              ↓                        │                         │
│         TroveManagerV2 ←──────────────┘                        │
│              ↓                                                  │
│         LiquidityCore ────→ StabilityPool                      │
│              ↓                    ↓                             │
│    UnifiedLiquidityPool      (absorbs debt)                    │
│              ↓                                                  │
│         SortedTroves                                            │
│                                                                 │
│  Collateral Flow:                                               │
│  User deposits 10 ETH → Sits in LiquidityCore                  │
│                      → Used ONLY for CDP backing               │
│                      → Idle capital (0% yield) ❌              │
└────────────────────────────────────────────────────────────────┘
```

**Problem**: Collateral sits idle, earning 0% yield!

---

## 🚀 V2 + AMM Architecture (What We're Building)

```
┌────────────────────────────────────────────────────────────────┐
│               V2 + AMM UNIFIED LIQUIDITY LAYER                  │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  User deposits 10 ETH collateral                                │
│         ↓                                                       │
│    BorrowerOperationsV2 / TroveManagerV2                       │
│         ↓                                                       │
│    LiquidityCore (tracks total collateral)                     │
│         ↓                                                       │
│    CapitalEfficiencyEngine (NEW!) ←───────┐                   │
│         │                                   │                   │
│         ├─ 30% (3 ETH) → Reserve Buffer    │                   │
│         ├─ 40% (4 ETH) → FluidAMM          │                   │
│         ├─ 20% (2 ETH) → Vaults (future)   │                   │
│         └─ 10% (1 ETH) → Staking (future)  │                   │
│                    ↓                        │                   │
│              FluidAMM Pools ────────────────┘                   │
│               (WETH/USDF)                                       │
│               (WETH/WBTC)                                       │
│                    ↓                                            │
│            Trading Fees Earned                                  │
│          (0.3% per swap → 0.13% to protocol)                   │
│                                                                 │
│  Result: Collateral earns yield while backing CDP! ✅          │
└────────────────────────────────────────────────────────────────┘
```

---

## 📦 New Components to Build

### **1. FluidAMM.sol** (Core DEX)
**Purpose**: Constant product AMM (Uniswap V2 style)

**Key Functions**:
```solidity
contract FluidAMM {
    // Core AMM operations
    function addLiquidity(...) external returns (uint256 liquidity);
    function removeLiquidity(...) external returns (uint256 amountA, uint256 amountB);
    function swap(...) external returns (uint256 amountOut);

    // Internal pricing
    function getReserves() public view returns (uint112 reserveA, uint112 reserveB);
    function getAmountOut(uint256 amountIn, ...) public view returns (uint256 amountOut);

    // LP token
    function mint(address to) internal returns (uint256 liquidity);
    function burn(address to) internal returns (uint256 amount0, uint256 amount1);
}
```

**Integration Points**:
- Receives collateral from `CapitalEfficiencyEngine`
- Holds LP tokens representing protocol-owned liquidity
- Sends trading fees back to `LiquidityCore`

---

### **2. CapitalEfficiencyEngine.sol** (Allocation Manager)
**Purpose**: Decides how to allocate idle collateral across AMM, vaults, staking

**Key Functions**:
```solidity
contract CapitalEfficiencyEngine {
    // Allocation logic
    function allocateCollateral(address asset, uint256 amount) external;
    function rebalance(address asset) external;
    function withdrawFromAMM(address asset, uint256 amount) external;

    // Safety checks
    function getAvailableForAllocation(address asset) public view returns (uint256);
    function getRequiredReserve(address asset) public view returns (uint256);
}
```

**Integration Points**:
- Queries `LiquidityCore` for total collateral
- Queries `TroveManagerV2` for active debt
- Calculates safe allocation (30% buffer always maintained)
- Calls `FluidAMM.addLiquidity()` to deploy capital
- Emergency: Can withdraw from AMM if collateral needed

---

### **3. DEXRouter.sol** (Swap Router)
**Purpose**: Routes swaps through AMM pairs, handles multi-hop trades

**Key Functions**:
```solidity
contract DEXRouter {
    // User-facing swap functions
    function swapExactTokensForTokens(...) external returns (uint256[] memory amounts);
    function swapTokensForExactTokens(...) external returns (uint256[] memory amounts);

    // Multi-hop routing
    function getAmountsOut(uint256 amountIn, address[] path) public view returns (uint256[]);
    function getOptimalPath(address tokenIn, address tokenOut) public view returns (address[]);
}
```

**Integration Points**:
- Front-end for users to interact with AMM
- Protects against slippage
- Supports multi-asset swaps (USDF → WETH → WBTC)

---

### **4. LPToken.sol** (Liquidity Provider Token)
**Purpose**: ERC20 representing shares in AMM pools

**Key Functions**:
```solidity
contract LPToken is ERC20 {
    // Standard ERC20
    // Minted when liquidity added
    // Burned when liquidity removed
}
```

**Integration Points**:
- Issued by `FluidAMM`
- Held by `CapitalEfficiencyEngine` (protocol-owned liquidity)
- Can be staked for rewards (Phase 2)

---

## 🔄 Data Flow Analysis

### **Flow 1: User Opens Trove (With AMM)**

```
1. User calls borrowerOps.openTrove(WETH, 0.05%, 10 ETH, 10000 USDF)
   ├─ Transfer 10 ETH to LiquidityCore
   ├─ LiquidityCore.depositCollateral(WETH, user, 10 ETH)
   ├─ Update _assetLiquidity[WETH].collateralReserve += 10 ETH
   └─ Mint 10,000 USDF to user

2. CapitalEfficiencyEngine.onCollateralDeposit(WETH, 10 ETH) ← NEW!
   ├─ Calculate safe allocation:
   │  ├─ Total collateral: 100 ETH
   │  ├─ Total debt: 150,000 USDF
   │  ├─ Required reserve (MCR * debt / price): 82.5 ETH
   │  ├─ Buffer (30%): 90 ETH
   │  └─ Available for allocation: 100 - 90 = 10 ETH
   │
   ├─ Allocation decision:
   │  ├─ 40% to AMM: 4 ETH
   │  ├─ 20% to Vaults: 2 ETH (future)
   │  └─ 10% to Staking: 1 ETH (future)
   │
   └─ Execute allocation:
      ├─ LiquidityCore.transferCollateral(WETH, FluidAMM, 4 ETH)
      └─ FluidAMM.addLiquidity(WETH, USDF, 4 ETH, 8000 USDF)
```

---

### **Flow 2: User Swaps on AMM**

```
1. User calls dexRouter.swap(USDF, WETH, 1000 USDF, minOut)
   └─ DEXRouter.swapExactTokensForTokens(...)

2. DEXRouter routes to FluidAMM
   └─ FluidAMM.swap(USDF, WETH, 1000 USDF, minOut)

3. FluidAMM executes constant product formula
   ├─ x * y = k (1000 WETH * 2M USDF = 2B)
   ├─ New reserves after swap:
   │  ├─ USDF: 2M + 1000 = 2,001,000
   │  └─ WETH: 2B / 2,001,000 = 999.5 ETH
   ├─ amountOut = 1000 - 999.5 = 0.5 ETH
   ├─ Trading fee (0.3%): 0.0015 ETH
   └─ User receives: 0.4985 ETH

4. Fee distribution
   ├─ 0.17% (0.00085 ETH) → LPs (stays in pool)
   └─ 0.13% (0.00065 ETH) → Protocol treasury
      └─ FluidAMM.collectFees() → LiquidityCore
```

---

### **Flow 3: Liquidation Needs Collateral (Emergency Withdrawal)**

```
1. Liquidation occurs, need to return collateral to user
   └─ TroveManagerV2.liquidate(bob, WETH)

2. LiquidityCore.withdrawCollateral(WETH, bob, 10 ETH)
   ├─ Check: collateralReserve = 90 ETH (not enough!)
   └─ Trigger emergency withdrawal from AMM

3. CapitalEfficiencyEngine.emergencyWithdraw(WETH, 10 ETH)
   ├─ FluidAMM.removeLiquidity(WETH, USDF, lpTokens)
   ├─ Receive 10 ETH + 20,000 USDF
   ├─ Transfer 10 ETH to LiquidityCore
   └─ Update allocation tracking

4. Complete liquidation flow
   └─ Transfer 10 ETH to liquidator
```

---

## 🔗 Integration Matrix

| Component | Integrates With | Purpose | Data Exchange |
|-----------|----------------|---------|---------------|
| **FluidAMM** | LiquidityCore | Receives collateral | `transferCollateral(asset, amm, amount)` |
| **FluidAMM** | CapitalEfficiencyEngine | Reports LP positions | `balanceOf(engine)` |
| **FluidAMM** | DEXRouter | Executes swaps | `swap(tokenIn, tokenOut, amount)` |
| **CapitalEfficiencyEngine** | LiquidityCore | Queries collateral | `getCollateralReserve(asset)` |
| **CapitalEfficiencyEngine** | TroveManagerV2 | Queries debt | `getTotalDebt(asset)` |
| **CapitalEfficiencyEngine** | FluidAMM | Adds/removes liquidity | `addLiquidity()`, `removeLiquidity()` |
| **DEXRouter** | FluidAMM | Routes swaps | `getReserves()`, `swap()` |
| **DEXRouter** | PriceOracle | Price validation | `getPrice(asset)` |

---

## 🛡️ Safety Mechanisms

### **1. Collateral Reserve Buffer (30%)**
```solidity
// Always maintain 30% buffer for withdrawals
function getRequiredReserve(address asset) public view returns (uint256) {
    uint256 totalCollateral = liquidityCore.getCollateralReserve(asset);
    return totalCollateral * RESERVE_BUFFER_PCT / 100; // 30%
}
```

### **2. Maximum Allocation Limits**
```solidity
// Never allocate more than 40% to AMM
uint256 public constant MAX_AMM_ALLOCATION = 40; // 40%
uint256 public constant MAX_VAULT_ALLOCATION = 20; // 20%
uint256 public constant MAX_STAKING_ALLOCATION = 10; // 10%
```

### **3. Circuit Breakers**
```solidity
// Pause AMM if:
// - Utilization > 90%
// - Collateral ratio < 120%
// - Large price movement detected
function checkCircuitBreakers() internal view {
    uint256 utilization = getUtilization();
    require(utilization < 9000, "Circuit breaker: High utilization");

    uint256 collateralRatio = getCollateralRatio();
    require(collateralRatio > 1200, "Circuit breaker: Low collateral ratio");
}
```

### **4. Emergency Withdrawal**
```solidity
// Pull liquidity from AMM if needed
function emergencyWithdrawFromAMM(address asset, uint256 amount) external onlyTroveManager {
    uint256 lpTokens = calculateLPTokens(asset, amount);
    fluidAMM.removeLiquidity(asset, usdf, lpTokens);

    // Return to LiquidityCore
    IERC20(asset).transfer(address(liquidityCore), amount);
}
```

---

## 📊 State Management

### **LiquidityCore State (Existing)**
```solidity
struct AssetLiquidity {
    uint128 collateralReserve;   // Total collateral in reserve
    uint128 debtReserve;          // Total debt
    uint128 borrowedFromUnified;  // Borrowed from UnifiedLiquidityPool
    uint128 pendingRewards;       // Liquidation rewards
    uint32 lastUpdateTime;
    bool isActive;
}
```

### **New State: CapitalAllocation Tracking**
```solidity
struct CapitalAllocation {
    uint128 totalCollateral;      // Total collateral for this asset
    uint128 reserveBuffer;        // Amount in reserve (30%)
    uint128 allocatedToAMM;       // Amount in AMM pools
    uint128 allocatedToVaults;    // Amount in vaults (future)
    uint128 allocatedToStaking;   // Amount in staking (future)
    uint128 lpTokensOwned;        // LP tokens held by protocol
    uint32 lastRebalance;
}
```

### **FluidAMM State**
```solidity
struct PairInfo {
    address token0;
    address token1;
    uint112 reserve0;
    uint112 reserve1;
    uint32 blockTimestampLast;
    uint256 kLast;                // For protocol fee calculation
    uint256 totalSupply;          // LP token supply
}
```

---

## 🎨 Architectural Decisions

### **Decision 1: Protocol-Owned Liquidity (POL)**
**Choice**: Protocol owns LP tokens, not individual users

**Rationale**:
- Simplifies accounting (no per-user LP tracking)
- Protocol captures 100% of trading fees
- Users benefit via reduced borrowing fees
- Easier to rebalance

**Implementation**:
```solidity
// CapitalEfficiencyEngine holds LP tokens
mapping(address => uint256) public lpTokenBalance; // asset => LP tokens

// Users never see LP tokens
// They only see reduced borrowing fees or rewards
```

---

### **Decision 2: Lazy Rebalancing**
**Choice**: Only rebalance when necessary, not on every deposit

**Rationale**:
- Saves gas (rebalancing is expensive)
- Most deposits don't meaningfully change allocation
- Can trigger manually or via keeper bot

**Implementation**:
```solidity
function shouldRebalance(address asset) public view returns (bool) {
    CapitalAllocation memory alloc = allocations[asset];
    uint256 targetAMM = alloc.totalCollateral * TARGET_AMM_PCT / 100;
    uint256 currentAMM = alloc.allocatedToAMM;

    // Rebalance if drift > 10%
    uint256 drift = currentAMM > targetAMM
        ? currentAMM - targetAMM
        : targetAMM - currentAMM;

    return drift > (targetAMM / 10); // 10% drift threshold
}
```

---

### **Decision 3: Single AMM Contract (Not Factory)**
**Choice**: One FluidAMM contract with multiple pools

**Rationale**:
- Simpler than Uniswap V2 factory pattern
- Fewer contract deployments
- Easier access control
- Sufficient for initial launch (WETH/USDF, WETH/WBTC)

**Implementation**:
```solidity
contract FluidAMM {
    // Multiple pools in one contract
    mapping(bytes32 => PairInfo) public pairs;

    function getPairKey(address tokenA, address tokenB) public pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1));
    }
}
```

---

### **Decision 4: Oracle Integration for Safety**
**Choice**: Use existing PriceOracle to validate AMM prices

**Rationale**:
- Prevents manipulation attacks
- Ensures AMM prices stay within reasonable bounds
- Can pause AMM if price deviation > 5%

**Implementation**:
```solidity
function validatePrice(address asset, uint256 ammPrice) internal view {
    uint256 oraclePrice = priceOracle.getPrice(asset);
    uint256 deviation = ammPrice > oraclePrice
        ? (ammPrice - oraclePrice) * 100 / oraclePrice
        : (oraclePrice - ammPrice) * 100 / oraclePrice;

    require(deviation < 5, "AMM price deviation too high");
}
```

---

## 📈 Revenue Flow

### **Trading Fees (0.3% per swap)**
```
Swap: 1000 USDF → 0.5 ETH
Fee: 0.3% = 0.0015 ETH

Distribution:
├─ 0.17% (0.00085 ETH) → Stays in AMM pool (compounds LP value)
└─ 0.13% (0.00065 ETH) → Protocol treasury
   └─ Collected via FluidAMM.collectFees()
   └─ Sent to LiquidityCore
   └─ Can be:
      ├─ Distributed to governance stakers
      ├─ Used to buy back protocol tokens
      └─ Added to insurance fund
```

### **User Benefit from AMM**
```
User deposits 10 ETH collateral:
├─ 3 ETH in reserve (earns 0%)
├─ 4 ETH in AMM (earns trading fees)
└─ 3 ETH in vaults/staking (earns yield)

AMM earnings:
├─ $100k daily volume on WETH/USDF pool
├─ 0.13% protocol fee = $130/day
├─ User's 4 ETH = 0.4% of 1000 ETH pool
└─ User earns: $130 * 0.4% = $0.52/day = $190/year

Result: User's borrowing fee reduced by AMM earnings!
```

---

## 🚀 Implementation Roadmap

### **Week 1: Core AMM**
```
Day 1-2: FluidAMM.sol
├─ Constant product formula (x * y = k)
├─ addLiquidity() / removeLiquidity()
├─ swap() with fee calculation
└─ LP token minting/burning

Day 3-4: DEXRouter.sol
├─ swapExactTokensForTokens()
├─ swapTokensForExactTokens()
├─ Multi-hop routing
└─ Slippage protection

Day 5: Integration
├─ Connect to PriceOracle
├─ Connect to AccessControl
└─ Testing
```

### **Week 2: Capital Efficiency**
```
Day 1-2: CapitalEfficiencyEngine.sol
├─ Allocation logic
├─ Rebalancing algorithm
├─ Safety checks
└─ Emergency withdrawal

Day 3-4: LiquidityCore Integration
├─ Add hooks for AMM allocation
├─ Update state tracking
└─ Event emissions

Day 5: Testing
├─ Integration tests
├─ Gas profiling
└─ Edge cases
```

### **Week 3: Polish & Deploy**
```
Day 1-2: Optimization
├─ Gas optimization
├─ Security review
└─ Code cleanup

Day 3-4: Documentation
├─ Architecture docs
├─ Integration guide
└─ User guide

Day 5: Deployment
├─ Deploy to testnet
├─ Verify contracts
└─ Initial liquidity provision
```

---

## ✅ Pre-Implementation Checklist

- [x] V2 CDP system complete (BorrowerOps, TroveManager)
- [x] StabilityPool integrated
- [x] LiquidityCore tracks all collateral
- [x] UnifiedLiquidityPool exists (can be enhanced)
- [x] PriceOracle functional
- [x] AccessControlManager in place
- [ ] FluidAMM implementation
- [ ] CapitalEfficiencyEngine implementation
- [ ] DEXRouter implementation
- [ ] Integration tests
- [ ] Gas profiling

---

## 🎯 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Capital Utilization** | 70% | (AMM + Vaults) / Total Collateral |
| **Trading Volume** | $100k/day | sum(swap amounts) |
| **Protocol Revenue** | $130/day | Trading fees * 0.13% |
| **Gas Cost (Swap)** | <100k gas | gasUsed per swap() |
| **Price Stability** | <5% deviation | abs(AMM price - Oracle price) |

---

## 🔜 Next Steps

**Ready to implement?** I can start building:

1. **FluidAMM.sol** - Constant product AMM with all optimizations
2. **Interface definitions** (IFluidAMM, ICapitalEfficiencyEngine)
3. **Comprehensive test suite**
4. **Gas profiling benchmarks**

**Estimated completion**: 2-3 weeks for full AMM + Capital Efficiency integration

---

**Status**: ✅ Architecture analyzed, ready for implementation
**Last Updated**: 2025-01-16
**Complexity**: Medium-High (but well-defined)
**Risk**: Low (proven AMM model + safety mechanisms)

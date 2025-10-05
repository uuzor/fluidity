# Next Steps - Development Roadmap

## Current Status (October 3, 2025)

### ✅ Completed
1. **5 Gas Optimization Libraries** (102 tests passing)
   - TransientStorage, PackedTrove, CalldataDecoder, BatchOperations, GasOptimizedMath

2. **UnifiedLiquidityPool** (32 tests passing, 3.4% gas savings)
   - Multi-asset liquidity management
   - Borrow/lend functionality
   - DEX integration hooks

3. **LiquidityCore** (34 tests passing, 7% gas savings)
   - Centralized pool management
   - Packed storage (3 slots)
   - TransientStorage reentrancy

**Total: 168 tests passing, All contracts in OrganisedSecured/ ✅**

---

## Development Flow: What to Build Next

### Phase 1: Price Oracle Integration (CRITICAL - Next Immediate Task)

**Why First**: UnifiedLiquidityPool currently uses mock pricing. This blocks production readiness.

**Tasks**:
1. Create `PriceOracle.sol` in `OrganisedSecured/core/`
   - Integrate Chainlink price feeds
   - Add price staleness checks
   - Support multiple price sources (Chainlink, Pyth, TWAP)
   - Cache prices in transient storage for gas savings

2. Update `UnifiedLiquidityPool.sol`:
   - Replace mock pricing logic
   - Add oracle integration
   - Test with real price data

3. Create comprehensive tests:
   - Price feed failures
   - Stale price handling
   - Oracle manipulation scenarios

**Files to Create**:
```
contracts/OrganisedSecured/
├── core/
│   └── PriceOracle.sol
├── interfaces/
│   └── IPriceOracle.sol
└── test/
    └── integration/
        └── PriceOracle.test.ts
```

**Expected Timeline**: 1 session (2-3 hours)

---

### Phase 2: BorrowerOperations (Core Lending)

**Why Second**: Foundation for user interactions with the protocol

**Tasks**:
1. Create `BorrowerOperations.sol`:
   - `openTrove()` - Create new CDP
   - `closeTrove()` - Close CDP and repay debt
   - `adjustTrove()` - Add/remove collateral, borrow/repay
   - `claimCollateral()` - Claim excess collateral after liquidation

2. Apply ALL gas optimizations:
   - Use TransientStorage for reentrancy
   - Use PackedTrove for storage
   - Use CalldataDecoder for parameters
   - Use BatchOperations for token transfers
   - Target: <200k gas for openTrove (vs ~450k unoptimized)

3. Integration with existing contracts:
   - LiquidityCore for collateral/debt tracking
   - PriceOracle for collateral valuation
   - SortedTroves for hint system

**Files to Create**:
```
contracts/OrganisedSecured/
├── core/
│   └── BorrowerOperations.sol
├── interfaces/
│   └── IBorrowerOperations.sol
└── test/
    └── integration/
        └── BorrowerOperations.test.ts
```

**Expected Timeline**: 2 sessions (4-5 hours)

**Gas Targets**:
- openTrove: <200k gas (target: 195k)
- closeTrove: <80k gas (target: 79k)
- adjustTrove: <150k gas

---

### Phase 3: TroveManager (Liquidation Engine)

**Why Third**: Handles trove lifecycle and liquidations

**Tasks**:
1. Create `TroveManager.sol`:
   - `liquidate()` - Single trove liquidation
   - `batchLiquidate()` - Multiple trove liquidations
   - `redeemCollateral()` - USDF redemption mechanism
   - Trove status tracking

2. Gas Optimizations:
   - Packed trove storage
   - Batch liquidation processing
   - Transient storage for intermediate calculations
   - Target: <120k gas per liquidation

3. Integration:
   - LiquidityCore for collateral distribution
   - PriceOracle for health factor calculations
   - StabilityPool for liquidation proceeds

**Files to Create**:
```
contracts/OrganisedSecured/
├── core/
│   └── TroveManager.sol
├── interfaces/
│   └── ITroveManager.sol
└── test/
    └── integration/
        └── TroveManager.test.ts
```

**Expected Timeline**: 2 sessions (4-5 hours)

---

### Phase 4: StabilityPool (Liquidation Absorber)

**Why Fourth**: Provides liquidity for liquidations and rewards depositors

**Tasks**:
1. Create `StabilityPool.sol`:
   - `provideToSP()` - Deposit USDF
   - `withdrawFromSP()` - Withdraw USDF + gains
   - `liquidate()` - Absorb liquidated debt
   - Reward distribution (collateral gains)

2. Gas Optimizations:
   - Packed deposit data
   - Efficient reward calculation
   - Epoch/scale tracking for rewards

**Files to Create**:
```
contracts/OrganisedSecured/
├── core/
│   └── StabilityPool.sol
├── interfaces/
│   └── IStabilityPool.sol
└── test/
    └── integration/
        └── StabilityPool.test.ts
```

**Expected Timeline**: 1-2 sessions (3-4 hours)

---

### Phase 5: DEX Full Integration

**Why Fifth**: Complete the DEX-Lending liquidity sharing

**Tasks**:
1. Create `FluidAMM.sol` (gas-optimized):
   - Swap functionality
   - Liquidity provision
   - Integration with UnifiedLiquidityPool
   - Dynamic routing

2. Cross-protocol features:
   - Liquidity borrowing for swaps
   - Flash loans
   - Arbitrage prevention

**Files to Create**:
```
contracts/OrganisedSecured/
├── dex/
│   └── FluidAMM.sol
├── interfaces/
│   └── IFluidAMM.sol
└── test/
    └── integration/
        └── FluidAMM.test.ts
```

**Expected Timeline**: 2 sessions (4-5 hours)

---

### Phase 6: Advanced Features

1. **Governance**:
   - FluidToken voting
   - Protocol parameter updates
   - Emergency actions

2. **Yield Strategies**:
   - Vault integrations
   - Automated yield optimization
   - Risk-adjusted returns

3. **Frontend Integration**:
   - ABI exports
   - SDK creation
   - Documentation

---

## Recommended Build Order

### Week 1: Price Oracle + BorrowerOperations
```
Day 1-2: Price Oracle
├── Implement Chainlink integration
├── Add price caching with TransientStorage
├── Test with mock and real feeds
└── 30+ tests

Day 3-5: BorrowerOperations
├── Implement all trove operations
├── Apply full gas optimization stack
├── Integration tests with LiquidityCore
└── 40+ tests
```

### Week 2: TroveManager + StabilityPool
```
Day 1-3: TroveManager
├── Liquidation logic
├── Batch operations
├── Redemption mechanism
└── 35+ tests

Day 4-5: StabilityPool
├── Deposit/withdrawal
├── Reward distribution
├── Integration with TroveManager
└── 30+ tests
```

### Week 3: DEX Integration + Polish
```
Day 1-3: FluidAMM
├── Swap mechanism
├── UnifiedPool integration
├── Flash loans
└── 40+ tests

Day 4-5: Integration & Optimization
├── End-to-end tests
├── Gas profiling
├── Security review
└── Documentation
```

---

## Critical Design Decisions

### 1. Use SortedTroves or Build New?
**Decision**: Port existing `SortedTroves.sol` to OrganisedSecured

**Reason**:
- Already implemented and tested
- Hint system is complex
- Focus optimization on new contracts

**Action**: Copy and optimize SortedTroves in next session

### 2. Single Oracle or Multiple Sources?
**Decision**: Support multiple oracle sources with fallback

**Reason**:
- Chainlink for primary pricing
- Pyth for backup
- TWAP for manipulation resistance

**Implementation**: Adapter pattern with priority ordering

### 3. Flash Loan Integration?
**Decision**: Yes, integrate from the start

**Reason**:
- Natural fit with UnifiedLiquidityPool
- Revenue source for protocol
- Already have infrastructure

---

## Success Metrics

### Per-Phase Goals:

**Phase 1 (Price Oracle)**:
- ✅ Multiple oracle support
- ✅ <5,000 gas for cached price reads
- ✅ Failover mechanisms tested

**Phase 2 (BorrowerOperations)**:
- ✅ <200k gas for openTrove
- ✅ <80k gas for closeTrove
- ✅ 100% test coverage

**Phase 3 (TroveManager)**:
- ✅ <120k gas per liquidation
- ✅ Batch liquidation support
- ✅ Redemption mechanism

**Phase 4 (StabilityPool)**:
- ✅ <100k gas for deposits
- ✅ Efficient reward distribution
- ✅ Integration complete

**Phase 5 (DEX)**:
- ✅ <100k gas for swaps
- ✅ Flash loans working
- ✅ Cross-protocol liquidity

---

## Next Session Checklist

### Immediate (Next Session):

- [ ] Create PriceOracle.sol with Chainlink integration
- [ ] Add IPriceOracle.sol interface
- [ ] Write 30+ tests for price oracle
- [ ] Update UnifiedLiquidityPool to use real oracle
- [ ] Verify all existing tests still pass

### Commands to Run:

```bash
# Create new files
touch contracts/OrganisedSecured/core/PriceOracle.sol
touch contracts/OrganisedSecured/interfaces/IPriceOracle.sol
touch test/OrganisedSecured/integration/PriceOracle.test.ts

# After implementation
npx hardhat compile
npx hardhat test test/OrganisedSecured/integration/

# Gas profiling
npx hardhat test --grep "Gas Profiling"
```

---

## File Organization (Updated)

```
contracts/OrganisedSecured/
├── core/                           # Core protocol contracts
│   ├── LiquidityCore.sol          ✅ (34 tests)
│   ├── UnifiedLiquidityPool.sol   ✅ (32 tests)
│   ├── PriceOracle.sol            ⏭️ NEXT
│   ├── BorrowerOperations.sol     📋 Phase 2
│   ├── TroveManager.sol           📋 Phase 3
│   ├── StabilityPool.sol          📋 Phase 4
│   └── SortedTroves.sol           📋 Phase 2
│
├── dex/                           # DEX components
│   └── FluidAMM.sol               📋 Phase 5
│
├── interfaces/                    # Contract interfaces
│   ├── ILiquidityCore.sol         ✅
│   ├── IPriceOracle.sol           ⏭️ NEXT
│   ├── IBorrowerOperations.sol    📋 Phase 2
│   ├── ITroveManager.sol          📋 Phase 3
│   └── IStabilityPool.sol         📋 Phase 4
│
├── libraries/                     # Gas optimization libraries
│   ├── TransientStorage.sol       ✅ (5 tests)
│   ├── PackedTrove.sol           ✅ (7 tests)
│   ├── CalldataDecoder.sol       ✅ (14 tests)
│   ├── BatchOperations.sol       ✅ (38 tests)
│   └── GasOptimizedMath.sol      ✅ (38 tests)
│
├── utils/                         # Shared utilities
│   ├── OptimizedSecurityBase.sol  ✅
│   └── AccessControlManager.sol   ✅
│
└── mocks/                         # Test mocks
    └── MockERC20.sol              ✅
```

---

## Questions to Consider

Before starting next phase:

1. **Which chain to deploy on first?**
   - Sonic (low fees, good for testing)
   - Ethereum mainnet (requires more optimization)
   - L2 (Arbitrum, Optimism)

2. **Collateral types to support?**
   - ETH, wBTC, stablecoins
   - LSTs (Liquid staking tokens)
   - LP tokens

3. **Governance model?**
   - Timelock delays
   - Multi-sig requirements
   - Community voting thresholds

---

## Summary

**Completed**: 8 contracts, 168 tests, gas optimization framework ✅

**Next Immediate**: Price Oracle (1 session)

**Then**: BorrowerOperations → TroveManager → StabilityPool → DEX

**Timeline**: ~3 weeks to full protocol

**Current Gas Savings**: 7% (test), 35% (production estimated)

---

*Updated: October 3, 2025*

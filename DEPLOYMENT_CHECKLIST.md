# 📋 Deployment Checklist - OrganisedSecured Contracts

## Pre-Deployment Verification

### ✅ Local Testing Complete

- [x] **BorrowerOperationsOptimized**: 20/20 tests passing
- [x] **PriceOracle**: 32/32 tests passing
- [x] **All dependencies**: Compiling without errors
- [x] **Dry run test**: Passed successfully

### ✅ Contract Readiness

| Contract | Status | Gas Optimization | Tests |
|----------|--------|------------------|-------|
| AccessControlManager | ✅ Ready | Standard | Inherited |
| USDF | ✅ Ready | Standard | Inherited |
| MockERC20 | ✅ Ready | N/A (test) | ✅ |
| MockChainlinkFeed | ✅ Ready | N/A (test) | ✅ |
| PriceOracle | ✅ Ready | TransientStorage | 32/32 ✅ |
| UnifiedLiquidityPool | ✅ Ready | Packed storage | 32/32 ✅ |
| LiquidityCore | ✅ Ready | Packed storage (7%) | 34/34 ✅ |
| SortedTroves | ✅ Ready | Standard | ✅ |
| BorrowerOperationsOptimized | ✅ Ready | PackedTrove | 20/20 ✅ |

**Total Tests Passing**: 168 tests ✅

---

## Deployment Preparation

### Step 1: Environment Setup

```bash
# ✅ Check .env file exists
[ -f .env ] && echo "✅ .env exists" || echo "❌ .env missing - copy from .env.example"

# ✅ Verify PRIVATE_KEY is set
grep PRIVATE_KEY .env | grep -v "^#" && echo "✅ PRIVATE_KEY set" || echo "❌ PRIVATE_KEY not set"
```

### Step 2: Get Testnet Funds

- [ ] Visit https://faucet.soniclabs.com
- [ ] Request testnet ETH (minimum 0.02 ETH needed)
- [ ] Verify balance:
  ```bash
  npx hardhat console --network sonic-testnet
  # Then: ethers.formatEther(await ethers.provider.getBalance((await ethers.getSigners())[0].address))
  ```

### Step 3: Verify Compilation

```bash
# ✅ Clean compile
npx hardhat clean
npx hardhat compile

# Expected: "Compiled 54 Solidity files successfully (evm target: cancun)"
```

### Step 4: Run Dry Run Test

```bash
# ✅ Test all contract factories
npx hardhat run scripts/test-deployment-dry-run.ts

# Expected: "✅ DRY RUN PASSED - All Contracts Ready for Deployment!"
```

---

## Deployment Execution

### Deploy to Sonic Testnet

```bash
npx hardhat run scripts/deploy-organised-secured.ts --network sonic-testnet
```

**Expected Duration**: 5-10 minutes

**What Happens**:
1. **Deployment** (9 contracts):
   - AccessControlManager
   - USDF Token
   - Mock WETH (1M supply)
   - Mock Chainlink Feed ($2000 ETH)
   - PriceOracle
   - UnifiedLiquidityPool
   - LiquidityCore
   - SortedTroves
   - BorrowerOperationsOptimized

2. **Verification** (automatic):
   - Each contract verified on block explorer
   - 10-second delay between deployments

3. **Configuration** (automatic):
   - USDF mint/burn permissions
   - Access control roles
   - Oracle registration
   - Collateral activation
   - Borrowing fee setup

4. **Output**:
   - Console logs with all addresses
   - JSON file: `organised-secured-deployment-14601-{timestamp}.json`

### Success Indicators

- [ ] All 9 contracts deployed with addresses
- [ ] All contracts verified on block explorer
- [ ] Configuration completed without errors
- [ ] Deployment JSON file created
- [ ] ETH price test: $2000.0
- [ ] MCR: 1.1 (110%)
- [ ] Borrowing fee: 0.5%
- [ ] WETH active in LiquidityCore: true

---

## Post-Deployment Verification

### Immediate Checks (Console)

```bash
npx hardhat console --network sonic-testnet
```

```javascript
// Load deployment (UPDATE TIMESTAMP!)
const d = require('./organised-secured-deployment-14601-YOUR_TIMESTAMP.json');

// Get contracts
const priceOracle = await ethers.getContractAt("PriceOracle", d.addresses.priceOracle);
const borrowerOps = await ethers.getContractAt("BorrowerOperationsOptimized", d.addresses.borrowerOperationsOptimized);
const liquidityCore = await ethers.getContractAt("LiquidityCore", d.addresses.liquidityCore);

// ✅ Test 1: Price Oracle
const price = await priceOracle.getPrice(d.addresses.mockWETH);
console.log("ETH Price:", ethers.formatEther(price)); // Should be 2000.0

// ✅ Test 2: BorrowerOps constants
const MCR = await borrowerOps.MCR();
console.log("MCR:", ethers.formatEther(MCR)); // Should be 1.1

// ✅ Test 3: WETH activation
const isActive = await liquidityCore.isAssetActive(d.addresses.mockWETH);
console.log("WETH Active:", isActive); // Should be true

// ✅ Test 4: Borrowing fee
const feeRate = await borrowerOps.getBorrowingFeeRate(d.addresses.mockWETH);
console.log("Fee Rate:", Number(ethers.formatEther(feeRate)) * 100 + "%"); // Should be 0.5%
```

**Expected Results**:
- [ ] ETH Price: 2000.0
- [ ] MCR: 1.1
- [ ] WETH Active: true
- [ ] Fee Rate: 0.5%

### Functional Tests

#### Test 1: Open Trove

```javascript
// Load deployment
const d = require('./organised-secured-deployment-14601-YOUR_TIMESTAMP.json');
const [signer] = await ethers.getSigners();

// Get contracts
const borrowerOps = await ethers.getContractAt("BorrowerOperationsOptimized", d.addresses.borrowerOperationsOptimized);
const weth = await ethers.getContractAt("MockERC20", d.addresses.mockWETH);

// Mint WETH
await weth.mint(signer.address, ethers.parseEther("100"));
console.log("✅ Minted 100 WETH");

// Approve
await weth.approve(borrowerOps.target, ethers.parseEther("10"));
console.log("✅ Approved 10 WETH");

// Open trove
const tx = await borrowerOps.openTrove(
  d.addresses.mockWETH,
  ethers.parseEther("0.05"), // Max 5% fee
  ethers.parseEther("10"),   // 10 WETH collateral
  ethers.parseEther("10000"), // 10,000 USDF debt
  ethers.ZeroAddress,
  ethers.ZeroAddress
);

const receipt = await tx.wait();
console.log(`✅ Trove opened! Gas: ${receipt.gasUsed}`);

// Check gas usage
const gasUsed = Number(receipt.gasUsed);
console.log("Gas Target: <200,000");
console.log("Gas Used:", gasUsed);
console.log(gasUsed < 200000 ? "✅ PASSED" : "⚠️  Exceeds target");
```

**Expected Results**:
- [ ] Transaction succeeds
- [ ] Gas used: <200,000
- [ ] Trove becomes active

#### Test 2: Close Trove

```javascript
// Get USDF contract
const usdf = await ethers.getContractAt("USDF", d.addresses.usdf);

// Get trove debt
const [debt] = await borrowerOps.getEntireDebtAndColl(signer.address, d.addresses.mockWETH);
console.log("Debt to repay:", ethers.formatEther(debt));

// Approve USDF
await usdf.approve(borrowerOps.target, debt);

// Close trove
const tx = await borrowerOps.closeTrove(d.addresses.mockWETH);
const receipt = await tx.wait();
console.log(`✅ Trove closed! Gas: ${receipt.gasUsed}`);

// Check gas usage
const gasUsed = Number(receipt.gasUsed);
console.log("Gas Target: <80,000");
console.log("Gas Used:", gasUsed);
console.log(gasUsed < 80000 ? "✅ PASSED" : "⚠️  Exceeds target");
```

**Expected Results**:
- [ ] Transaction succeeds
- [ ] Gas used: <80,000
- [ ] Trove becomes inactive
- [ ] Collateral returned

#### Test 3: PriceOracle Caching

```javascript
const priceOracle = await ethers.getContractAt("PriceOracle", d.addresses.priceOracle);

// Test caching
const tx1 = await priceOracle.updateAndCachePrice(d.addresses.mockWETH);
const receipt1 = await tx1.wait();
console.log("First fetch (uncached):", receipt1.gasUsed);

// Note: Cached price only available in same transaction
// TransientStorage clears after transaction

// Expected: ~50,000 gas for uncached fetch
```

**Expected Results**:
- [ ] updateAndCachePrice succeeds
- [ ] Gas used: ~50,000 (uncached)

---

## Gas Benchmarks

Record actual gas usage:

| Operation | Target | Actual | Status |
|-----------|--------|--------|--------|
| openTrove | <200k | ______ | ⬜ |
| closeTrove | <80k | ______ | ⬜ |
| adjustTrove | <150k | ______ | ⬜ |
| getPrice (cached) | <5k | ______ | ⬜ |
| getPrice (uncached) | ~50k | ______ | ⬜ |

**View transactions on explorer**:
- https://testnet.sonicscan.com/address/{YOUR_DEPLOYER_ADDRESS}

---

## Troubleshooting

### Issue: Deployment fails at verification

**Symptoms**: Contract deploys but verification fails

**Solutions**:
1. **Wait and retry**: Sometimes explorer needs time to index
   ```bash
   # Manually verify after 1-2 minutes
   npx hardhat verify --network sonic-testnet <ADDRESS> <CONSTRUCTOR_ARGS>
   ```

2. **Check API key**: Ensure `SONICSCAN_TESTNET_API_KEY` is set in `.env`

3. **Skip verification**: Comment out `await verifyContract()` calls temporarily

### Issue: Out of gas

**Symptoms**: Transaction reverts with "out of gas"

**Solutions**:
1. Increase gas limit in hardhat.config.ts:
   ```typescript
   "sonic-testnet": {
     gas: 12000000, // Increase from 8000000
   }
   ```

2. Check deployer balance has enough ETH

### Issue: "Insufficient collateral ratio"

**Symptoms**: openTrove fails with this error

**Cause**: Your collateral ratio is below 110%

**Solution**: Increase collateral or decrease debt
```javascript
// Calculate required collateral:
const minCollateral = (debt / price) * 1.1;
console.log("Minimum collateral needed:", ethers.formatEther(minCollateral));
```

### Issue: "Asset not active"

**Symptoms**: Operations fail with asset not active

**Cause**: Asset not registered in LiquidityCore

**Solution**: The deployment script activates WETH automatically. If testing other assets:
```javascript
await liquidityCore.activateAsset(assetAddress);
```

---

## Success Criteria

Before considering deployment successful:

- [ ] All 9 contracts deployed
- [ ] All contracts verified on explorer
- [ ] Configuration completed (permissions, roles, oracle)
- [ ] openTrove test passed
- [ ] closeTrove test passed
- [ ] Gas benchmarks within targets
- [ ] No errors in console logs
- [ ] Deployment JSON saved

---

## Next Steps After Successful Deployment

1. **Testing Phase** (24-48 hours):
   - [ ] Test all BorrowerOperations functions
   - [ ] Test edge cases (minimum collateral, etc.)
   - [ ] Test PriceOracle edge cases (staleness, etc.)
   - [ ] Monitor for any issues

2. **Documentation**:
   - [ ] Record all gas benchmarks
   - [ ] Document any issues found
   - [ ] Update README with deployment addresses

3. **Security**:
   - [ ] Review access control permissions
   - [ ] Test emergency functions (freeze oracle, etc.)
   - [ ] Verify role assignments

4. **Future Development** (from NEXT_STEPS.md):
   - [ ] Phase 3: TroveManager (liquidation engine)
   - [ ] Phase 4: StabilityPool (liquidation absorber)
   - [ ] Phase 5: DEX integration
   - [ ] Phase 6: Governance & yield strategies

---

## Files Generated

After successful deployment:

```
solidity/
├── organised-secured-deployment-14601-{timestamp}.json  ← Deployment addresses
├── scripts/
│   ├── deploy-organised-secured.ts                      ← Main deployment script
│   ├── test-deployment-dry-run.ts                       ← Pre-deployment test
│   └── ORGANISED_SECURED_DEPLOYMENT.md                  ← Detailed guide
├── TESTNET_DEPLOYMENT_QUICKSTART.md                     ← Quick start guide
└── DEPLOYMENT_CHECKLIST.md                              ← This file
```

---

## Support & Resources

- **Quick Start**: `TESTNET_DEPLOYMENT_QUICKSTART.md`
- **Detailed Guide**: `scripts/ORGANISED_SECURED_DEPLOYMENT.md`
- **Next Steps**: `contracts/OrganisedSecured/NEXT_STEPS.md`
- **Tests**: `test/OrganisedSecured/integration/`
- **Block Explorer**: https://testnet.sonicscan.com
- **Faucet**: https://faucet.soniclabs.com

---

*Updated: October 5, 2025*
*Ready for testnet deployment ✅*

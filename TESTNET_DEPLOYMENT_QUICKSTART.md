# 🚀 Testnet Deployment - Quick Start Guide

## Purpose

Deploy **OrganisedSecured** contracts (BorrowerOperationsOptimized + PriceOracle) to Sonic testnet for testing.

---

## Prerequisites

### 1. Environment Setup

```bash
# Copy .env.example to .env
cp .env.example .env
```

Edit `.env` and add your private key:
```env
PRIVATE_KEY=your_private_key_here_without_0x_prefix
SONICSCAN_TESTNET_API_KEY=your_api_key_optional
```

### 2. Get Testnet ETH

- **Sonic Testnet Faucet**: https://faucet.soniclabs.com
- **Amount needed**: ~0.02 ETH (deployment cost)
- **Your deployer address**: Run `npx hardhat console` and check your address

---

## Deployment Steps

### Step 1: Verify Setup

```bash
# Test that all contracts compile and can be deployed
npx hardhat run scripts/test-deployment-dry-run.ts
```

**Expected output**: `✅ DRY RUN PASSED - All Contracts Ready for Deployment!`

### Step 2: Deploy to Sonic Testnet

```bash
npx hardhat run scripts/deploy-organised-secured.ts --network sonic-testnet
```

**Deployment time**: ~5-10 minutes (including verification)

**Expected output**:
```
🚀 DEPLOYING ORGANISEDSECURED CONTRACTS
======================================================================
📍 Network: sonic-testnet (Chain ID: 14601)
💼 Deployer: 0x...
💰 Balance: X.XX ETH

📦 [1/8] Deploying AccessControlManager...
   ✅ 0x...
   🔍 Verifying...
   ✅ Verified

... (continues for all 9 contracts)

⚙️  CONFIGURING CONTRACTS
======================================================================
✅ USDF permissions granted
✅ Access control roles configured
✅ WETH activated as collateral
✅ PriceOracle registered ($2000 ETH)
✅ Borrowing fee: 0.5%

🎉 DEPLOYMENT COMPLETE!
📋 DEPLOYED CONTRACTS:
...

💾 Deployment saved to: organised-secured-deployment-14601-{timestamp}.json
```

### Step 3: Save Deployment Addresses

The deployment script automatically creates a JSON file with all addresses:
```
organised-secured-deployment-14601-{timestamp}.json
```

**Keep this file safe** - you'll need it for testing!

---

## Testing Your Deployment

### Option 1: Hardhat Console (Recommended)

```bash
npx hardhat console --network sonic-testnet
```

```javascript
// Load deployment
const deployment = require('./organised-secured-deployment-14601-{YOUR_TIMESTAMP}.json');

// Get contracts
const borrowerOps = await ethers.getContractAt(
  "BorrowerOperationsOptimized",
  deployment.addresses.borrowerOperationsOptimized
);

const weth = await ethers.getContractAt(
  "MockERC20",
  deployment.addresses.mockWETH
);

const priceOracle = await ethers.getContractAt(
  "PriceOracle",
  deployment.addresses.priceOracle
);

// Test 1: Check ETH price
const price = await priceOracle.getPrice(deployment.addresses.mockWETH);
console.log("ETH Price:", ethers.formatEther(price)); // Should be 2000.0

// Test 2: Mint WETH to yourself
const [signer] = await ethers.getSigners();
await weth.mint(signer.address, ethers.parseEther("100"));
console.log("✅ Minted 100 WETH");

// Test 3: Check WETH balance
const balance = await weth.balanceOf(signer.address);
console.log("WETH Balance:", ethers.formatEther(balance));

// Test 4: Open a trove
const collateral = ethers.parseEther("10"); // 10 WETH
const usdfAmount = ethers.parseEther("10000"); // 10,000 USDF

// Approve BorrowerOps to spend WETH
await weth.approve(borrowerOps.target, collateral);
console.log("✅ Approved BorrowerOps");

// Open trove
console.log("🔓 Opening trove...");
const tx = await borrowerOps.openTrove(
  deployment.addresses.mockWETH,
  ethers.parseEther("0.05"), // Max 5% fee
  collateral,
  usdfAmount,
  ethers.ZeroAddress, // upperHint
  ethers.ZeroAddress  // lowerHint
);

const receipt = await tx.wait();
console.log(`✅ Trove opened! Gas used: ${receipt.gasUsed}`);

// Test 5: Check trove status
const isActive = await borrowerOps.isTroveActive(
  signer.address,
  deployment.addresses.mockWETH
);
console.log("Trove active:", isActive);

// Test 6: Get trove details
const [debt, coll] = await borrowerOps.getEntireDebtAndColl(
  signer.address,
  deployment.addresses.mockWETH
);
console.log("Debt:", ethers.formatEther(debt));
console.log("Collateral:", ethers.formatEther(coll));
```

### Option 2: Test Script

Create `test-live-deployment.ts`:

```typescript
import { ethers } from "hardhat";

async function main() {
  // IMPORTANT: Update this path to your actual deployment file
  const deployment = require('./organised-secured-deployment-14601-YOUR_TIMESTAMP.json');

  const [signer] = await ethers.getSigners();
  console.log("Testing with account:", signer.address);

  // Get contracts
  const borrowerOps = await ethers.getContractAt(
    "BorrowerOperationsOptimized",
    deployment.addresses.borrowerOperationsOptimized
  );

  const weth = await ethers.getContractAt(
    "MockERC20",
    deployment.addresses.mockWETH
  );

  const priceOracle = await ethers.getContractAt(
    "PriceOracle",
    deployment.addresses.priceOracle
  );

  // Test 1: Check price
  console.log("\n📊 Testing PriceOracle...");
  const price = await priceOracle.getPrice(deployment.addresses.mockWETH);
  console.log(`✅ ETH Price: $${ethers.formatEther(price)}`);

  // Test 2: Mint WETH
  console.log("\n💰 Minting WETH...");
  await weth.mint(signer.address, ethers.parseEther("100"));
  const balance = await weth.balanceOf(signer.address);
  console.log(`✅ WETH Balance: ${ethers.formatEther(balance)}`);

  // Test 3: Open trove
  console.log("\n🔓 Opening trove...");
  const collateral = ethers.parseEther("10");
  const usdfAmount = ethers.parseEther("10000");

  await weth.approve(borrowerOps.target, collateral);
  console.log("✅ Approved BorrowerOps");

  const tx = await borrowerOps.openTrove(
    deployment.addresses.mockWETH,
    ethers.parseEther("0.05"),
    collateral,
    usdfAmount,
    ethers.ZeroAddress,
    ethers.ZeroAddress
  );

  const receipt = await tx.wait();
  console.log(`✅ Trove opened! Gas: ${receipt.gasUsed}`);

  // Test 4: Check trove
  const [debt, coll] = await borrowerOps.getEntireDebtAndColl(
    signer.address,
    deployment.addresses.mockWETH
  );

  console.log(`\n📊 Trove Details:`);
  console.log(`   Debt: ${ethers.formatEther(debt)} USDF`);
  console.log(`   Collateral: ${ethers.formatEther(coll)} WETH`);
  console.log(`   Collateral Value: $${Number(ethers.formatEther(coll)) * Number(ethers.formatEther(price))}`);
  console.log(`   Collateral Ratio: ${(Number(ethers.formatEther(coll)) * Number(ethers.formatEther(price)) / Number(ethers.formatEther(debt)) * 100).toFixed(2)}%`);

  console.log("\n✅ ALL TESTS PASSED!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

Run it:
```bash
npx hardhat run test-live-deployment.ts --network sonic-testnet
```

---

## What Gets Deployed

| Contract | Purpose | Gas Optimizations |
|----------|---------|-------------------|
| **AccessControlManager** | Role-based permissions | Standard |
| **USDF** | Stablecoin (debt token) | Standard |
| **Mock WETH** | Test collateral (1M supply) | N/A (test only) |
| **Mock Chainlink Feed** | Test price feed ($2000) | N/A (test only) |
| **PriceOracle** | Gas-optimized oracle | TransientStorage caching (~2,500 gas/read) |
| **UnifiedLiquidityPool** | Cross-protocol liquidity | Packed storage (3.4% savings) |
| **LiquidityCore** | Centralized pool manager | Packed storage (7% savings) |
| **SortedTroves** | Trove ordering (hint system) | Standard |
| **BorrowerOperationsOptimized** | CDP management | PackedTrove (~85k gas savings) |

**Total deployment cost**: ~0.02 ETH @ 1 gwei (essentially free on testnet)

---

## Automatic Configuration

The deployment script automatically:
- ✅ Grants USDF mint/burn permissions to BorrowerOps and LiquidityCore
- ✅ Grants access control roles (BORROWER_OPS_ROLE)
- ✅ Registers WETH oracle ($2000, 1-hour heartbeat)
- ✅ Activates WETH as collateral
- ✅ Configures SortedTroves (max 10,000 troves)
- ✅ Sets borrowing fee (0.5%)
- ✅ Verifies all contracts on block explorer

---

## Gas Benchmarks

After testing, verify gas usage:

| Operation | Target | Your Result |
|-----------|--------|-------------|
| openTrove | <200k | ______ gas |
| closeTrove | <80k | ______ gas |
| adjustTrove | <150k | ______ gas |
| getPrice (cached) | <5k | ______ gas |
| getPrice (uncached) | ~50k | ______ gas |

**Check transaction details**: https://testnet.sonicscan.com/tx/{YOUR_TX_HASH}

---

## Troubleshooting

### Issue: "Insufficient funds"
**Solution**: Get more testnet ETH from https://faucet.soniclabs.com

### Issue: "Insufficient collateral ratio"
**Cause**: Your trove's collateral ratio is below 110%

**Solution**: Either:
- Increase collateral amount
- Decrease USDF borrow amount
- Formula: `(collateral × price) / debt >= 1.1`

Example:
```javascript
// ❌ Too risky (90% ratio):
collateral = 10 WETH ($20,000)
debt = 22,000 USDF
ratio = 20000 / 22000 = 0.909 (90.9%) → REJECTED

// ✅ Safe (200% ratio):
collateral = 10 WETH ($20,000)
debt = 10,000 USDF
ratio = 20000 / 10000 = 2.0 (200%) → ACCEPTED
```

### Issue: "Oracle not registered"
**Solution**: The deployment script registers WETH automatically. If you're testing with a different token, register it:
```javascript
await priceOracle.registerOracle(
  tokenAddress,
  chainlinkFeedAddress,
  3600 // heartbeat in seconds
);
```

### Issue: Verification failed
**Solution**: Manually verify:
```bash
npx hardhat verify --network sonic-testnet <CONTRACT_ADDRESS> <CONSTRUCTOR_ARG1> <CONSTRUCTOR_ARG2>
```

Example:
```bash
npx hardhat verify --network sonic-testnet 0x123... 0x456... 0x789...
```

---

## Block Explorers

- **Sonic Testnet**: https://testnet.sonicscan.com
- Check your deployer: `https://testnet.sonicscan.com/address/{YOUR_ADDRESS}`
- Check contracts: `https://testnet.sonicscan.com/address/{CONTRACT_ADDRESS}`

---

## What's Next?

After verifying everything works:

1. ✅ Test all BorrowerOperations functions
   - openTrove ✓
   - closeTrove
   - adjustTrove
   - claimCollateral

2. ✅ Test PriceOracle features
   - Price caching with TransientStorage
   - Staleness checks
   - Deviation limits
   - Emergency freeze

3. ✅ Test edge cases
   - Opening trove at minimum collateral ratio (110%)
   - Price fluctuations
   - Multiple troves from different accounts

4. ✅ Monitor for 24-48 hours on testnet

5. ✅ Deploy to mainnet (when ready)

---

## Support

- **Deployment Guide**: `scripts/ORGANISED_SECURED_DEPLOYMENT.md`
- **Contract Docs**: `contracts/OrganisedSecured/`
- **Tests**: `test/OrganisedSecured/integration/`
- **Next Steps**: `contracts/OrganisedSecured/NEXT_STEPS.md`

---

## Summary

```bash
# 1. Setup
cp .env.example .env
# Edit .env with your PRIVATE_KEY

# 2. Get testnet ETH
# Visit: https://faucet.soniclabs.com

# 3. Test locally
npx hardhat run scripts/test-deployment-dry-run.ts

# 4. Deploy to testnet
npx hardhat run scripts/deploy-organised-secured.ts --network sonic-testnet

# 5. Test on testnet
npx hardhat console --network sonic-testnet
# Then follow the testing examples above

# 6. Celebrate! 🎉
```

---

*Created: October 5, 2025*

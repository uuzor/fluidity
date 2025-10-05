# OrganisedSecured Deployment Guide

## Overview

This script deploys **only** the contracts in the `OrganisedSecured` folder for testing:
- ✅ BorrowerOperationsOptimized
- ✅ PriceOracle
- ✅ LiquidityCore
- ✅ UnifiedLiquidityPool
- ✅ SortedTroves
- ✅ Supporting infrastructure (AccessControl, USDF, Mock tokens)

**Purpose**: Test the optimized BorrowerOperations and PriceOracle on testnet before full protocol deployment.

## What Gets Deployed

```
1. AccessControlManager          - Role-based permissions
2. USDF Token                    - Stablecoin
3. Mock WETH                     - Test collateral (1M WETH minted)
4. Mock Chainlink Feed           - Test oracle ($2000 ETH price)
5. PriceOracle                   - Gas-optimized with TransientStorage
6. UnifiedLiquidityPool          - Cross-protocol liquidity
7. LiquidityCore                 - Packed storage (7% savings)
8. SortedTroves                  - Trove ordering
9. BorrowerOperationsOptimized   - Main contract (TransientStorage + PackedTrove)
```

## Automatic Configuration

The script automatically:
- ✅ Grants USDF mint/burn permissions
- ✅ Sets up access control roles
- ✅ Registers WETH in PriceOracle ($2000)
- ✅ Activates WETH as collateral
- ✅ Configures SortedTroves
- ✅ Sets borrowing fee (0.5%)
- ✅ Verifies all contracts on block explorer

## Deployment

### Prerequisites

```bash
# 1. Set up .env
echo "PRIVATE_KEY=your_private_key" > .env

# 2. Fund your deployer address with testnet ETH
# Get testnet ETH from: https://faucet.soniclabs.com (for Sonic)
```

### Deploy to Sonic Testnet

```bash
npx hardhat run scripts/deploy-organised-secured.ts --network sonic-testnet
```

### Expected Output

```
🚀 DEPLOYING ORGANISEDSECURED CONTRACTS
======================================================================
📍 Network: sonic-testnet (Chain ID: 14601)
💼 Deployer: 0x...
💰 Balance: 1.5 ETH

📦 [1/8] Deploying AccessControlManager...
   ✅ 0x1234...
   🔍 Verifying 0x1234...
   ✅ Verified

... (continues for all 9 contracts)

⚙️  CONFIGURING CONTRACTS
======================================================================
📝 Setting USDF permissions...
   ✅ USDF permissions granted
📝 Setting access control roles...
   ✅ BORROWER_OPS_ROLE granted
📝 Configuring SortedTroves...
   ✅ SortedTroves configured
📝 Setting borrowing fee...
   ✅ Borrowing fee: 0.5%

🧪 TESTING DEPLOYMENT
======================================================================
✅ ETH Price: $2000.0
✅ MCR: 1.1 (110%)
✅ MIN_NET_DEBT: 2000.0 USDF
✅ GAS_COMPENSATION: 200.0 USDF
✅ Borrowing Fee Rate: 0.5%
✅ WETH active in LiquidityCore: true

🎉 DEPLOYMENT COMPLETE!
======================================================================

📋 DEPLOYED CONTRACTS:
AccessControlManager:          0x1234...
USDF Token:                    0x5678...
Mock WETH:                     0x90ab...
Mock Chainlink Feed:           0xcdef...
PriceOracle:                   0x1122...
UnifiedLiquidityPool:          0x3344...
LiquidityCore:                 0x5566...
SortedTroves:                  0x7788...
BorrowerOperationsOptimized:   0x99aa...

💾 Deployment saved to: organised-secured-deployment-14601-1234567890.json

🚀 READY TO TEST!
```

## Testing After Deployment

### Option 1: Hardhat Console

```bash
npx hardhat console --network sonic-testnet
```

```javascript
// Load deployment addresses
const deployment = require('./organised-secured-deployment-14601-1234567890.json');

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
const price = await priceOracle.getPrice(deployment.addresses.mockWETH);
console.log("ETH Price:", ethers.formatEther(price)); // $2000.0

// Test 2: Open a trove
const collateral = ethers.parseEther("10"); // 10 WETH
const usdfAmount = ethers.parseEther("10000"); // 10,000 USDF

// Mint WETH to yourself (it's a mock, so we can mint)
await weth.mint(await ethers.provider.getSigner().getAddress(), collateral);

// Approve
await weth.approve(borrowerOps.address, collateral);

// Open trove
const tx = await borrowerOps.openTrove(
  deployment.addresses.mockWETH,
  ethers.parseEther("0.05"), // Max 5% fee
  collateral,
  usdfAmount,
  ethers.ZeroAddress, // upperHint
  ethers.ZeroAddress  // lowerHint
);

const receipt = await tx.wait();
console.log("Gas used:", receipt.gasUsed.toString());
// Should be optimized (~200-300k including external calls)

// Check trove is active
const isActive = await borrowerOps.isTroveActive(
  await ethers.provider.getSigner().getAddress(),
  deployment.addresses.mockWETH
);
console.log("Trove active:", isActive); // true

// Check debt and collateral
const [debt, coll] = await borrowerOps.getEntireDebtAndColl(
  await ethers.provider.getSigner().getAddress(),
  deployment.addresses.mockWETH
);
console.log("Debt:", ethers.formatEther(debt));
console.log("Collateral:", ethers.formatEther(coll));
```

### Option 2: Test Script

Create `test-deployment.ts`:

```typescript
import { ethers } from "hardhat";

async function main() {
  const deployment = require('./organised-secured-deployment-14601-1234567890.json');

  const [signer] = await ethers.getSigners();

  const borrowerOps = await ethers.getContractAt(
    "BorrowerOperationsOptimized",
    deployment.addresses.borrowerOperationsOptimized
  );

  const weth = await ethers.getContractAt(
    "MockERC20",
    deployment.addresses.mockWETH
  );

  // Mint WETH
  await weth.mint(signer.address, ethers.parseEther("100"));
  console.log("✅ Minted 100 WETH");

  // Approve
  await weth.approve(borrowerOps.address, ethers.parseEther("10"));
  console.log("✅ Approved 10 WETH");

  // Open trove
  console.log("🔓 Opening trove...");
  const tx = await borrowerOps.openTrove(
    deployment.addresses.mockWETH,
    ethers.parseEther("0.05"),
    ethers.parseEther("10"),
    ethers.parseEther("10000"),
    ethers.ZeroAddress,
    ethers.ZeroAddress
  );

  const receipt = await tx.wait();
  console.log(`✅ Trove opened! Gas: ${receipt.gasUsed}`);

  // Check trove
  const [debt, coll] = await borrowerOps.getEntireDebtAndColl(
    signer.address,
    deployment.addresses.mockWETH
  );

  console.log(`📊 Debt: ${ethers.formatEther(debt)} USDF`);
  console.log(`📊 Collateral: ${ethers.formatEther(coll)} WETH`);
}

main()
  .then(() => process.exit(0))
  .catch(console.error);
```

Run it:
```bash
npx hardhat run test-deployment.ts --network sonic-testnet
```

## Gas Benchmarks

After testing, verify gas usage matches targets:

| Operation | Target | Check in Explorer |
|-----------|--------|-------------------|
| openTrove | <200k | ______ gas |
| closeTrove | <80k | ______ gas |
| adjustTrove | <150k | ______ gas |

**Note**: Total transaction gas will be higher due to external calls. Check the contract's internal gas usage.

## What's Next

After verifying everything works:

1. ✅ Test all BorrowerOperations functions
   - openTrove ✓
   - closeTrove
   - adjustTrove
   - claimCollateral

2. ✅ Test PriceOracle features
   - Price updates
   - TransientStorage caching
   - Staleness checks
   - Emergency freeze

3. ✅ Monitor for 24-48 hours on testnet

4. ✅ Deploy full protocol (if needed) using `deploy-full-optimized.ts`

## Troubleshooting

### Issue: Out of gas

**Solution**: Increase gas limit in hardhat.config.ts:
```typescript
networks: {
  "sonic-testnet": {
    gas: 12000000, // Increase this
  }
}
```

### Issue: Verification failed

**Solution**: Manually verify:
```bash
npx hardhat verify --network sonic-testnet <ADDRESS> <CONSTRUCTOR_ARGS>
```

### Issue: "Insufficient collateral ratio"

**Solution**: Either:
- Increase collateral amount
- Decrease USDF amount
- Check: `(collateral * price) / debt >= 1.1`

## Deployment Cost

Approximate cost on Sonic testnet (@ 1 gwei):

| Contract | Gas | Cost |
|----------|-----|------|
| AccessControl | ~1.5M | ~0.0015 ETH |
| Tokens | ~6M | ~0.006 ETH |
| Oracle + Feed | ~3M | ~0.003 ETH |
| Core contracts | ~10M | ~0.01 ETH |
| **Total** | **~20M** | **~0.02 ETH** |

On Sonic testnet, this is essentially free!

## Files Generated

After deployment:
- `organised-secured-deployment-{chainId}-{timestamp}.json` - All addresses and config
- Verified contracts on block explorer

## Support

- Docs: `/contracts/OrganisedSecured/core/*.md`
- Tests: `/test/OrganisedSecured/integration/*.test.ts`
- GitHub Issues: Report problems

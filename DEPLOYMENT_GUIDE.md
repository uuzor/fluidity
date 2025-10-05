# Fluid Protocol - Complete Deployment Guide

## Overview

This guide covers deploying the complete Fluid Protocol with all gas optimizations to testnet/mainnet.

## Deployed Contracts

### Core Contracts (Gas Optimized)
- ✅ **BorrowerOperationsOptimized**: CDP operations with TransientStorage + PackedTrove
- ✅ **PriceOracle**: Chainlink integration with TransientStorage caching
- ✅ **LiquidityCore**: Centralized liquidity with packed storage
- ✅ **UnifiedLiquidityPool**: Cross-protocol liquidity sharing
- ✅ **SortedTroves**: Efficient trove ordering

### Supporting Contracts
- ✅ **USDF**: Stablecoin token
- ✅ **FluidToken**: Governance token
- ✅ **AccessControlManager**: Role-based permissions
- ✅ **FluidAMM** (Optional): DEX with unified liquidity

## Pre-Deployment Checklist

### 1. Environment Setup

```bash
# Install dependencies
npm install

# Set up .env file
cp .env.example .env
```

### 2. Configure .env

```env
# Private key (DO NOT COMMIT!)
PRIVATE_KEY=your_private_key_here

# Block explorer API keys (for verification)
SONIC_API_KEY=your_sonic_api_key
ETHERSCAN_API_KEY=your_etherscan_api_key

# RPC URLs (optional, using defaults from hardhat.config.ts)
SONIC_TESTNET_RPC=https://rpc.testnet.soniclabs.com
SONIC_MAINNET_RPC=https://rpc.soniclabs.com
```

### 3. Get Chainlink Feed Addresses

Before deploying to mainnet, get actual Chainlink price feed addresses:

**Sonic Testnet/Mainnet Feeds:**
- Visit: https://docs.chain.link/data-feeds/price-feeds/addresses
- Find: S/USD, ETH/USD, BTC/USD feeds for Sonic network
- Update `CHAINLINK_FEEDS` in `scripts/deploy-full-optimized.ts`

## Deployment Steps

### Option 1: Deploy Complete Optimized Application

```bash
# Deploy to Sonic testnet
npx hardhat run scripts/deploy-full-optimized.ts --network sonic-testnet

# Deploy to Sonic mainnet (CAUTION: REAL FUNDS)
npx hardhat run scripts/deploy-full-optimized.ts --network sonic-mainnet
```

**What This Deploys:**
1. AccessControlManager
2. USDF + FluidToken
3. PriceOracle (with Chainlink integration or mocks)
4. UnifiedLiquidityPool + LiquidityCore
5. SortedTroves
6. BorrowerOperationsOptimized
7. FluidAMM (optional)

**Automatic Configuration:**
- ✅ Sets up all permissions (USDF minting, access roles)
- ✅ Activates WETH as collateral
- ✅ Registers price oracles
- ✅ Configures borrowing fees
- ✅ Links all contracts together
- ✅ Verifies contracts on block explorer

### Option 2: Deploy PriceOracle Only

If you just need to deploy/update the price oracle:

```bash
npx hardhat run scripts/deploy-price-oracle.ts --network sonic-testnet
```

## Post-Deployment

### 1. Verify Deployment

Check the generated JSON file (e.g., `optimized-deployment-14601-1234567890.json`):

```json
{
  "addresses": {
    "borrowerOperationsOptimized": "0x...",
    "priceOracle": "0x...",
    "liquidityCore": "0x...",
    "usdf": "0x...",
    ...
  },
  "statistics": {
    "totalContracts": 10,
    "verifiedContracts": 10,
    "verificationRate": "100%"
  }
}
```

### 2. Test Basic Operations

```bash
# Run integration tests against deployed contracts
npx hardhat test test/OrganisedSecured/integration/BorrowerOperationsOptimized.test.ts --network sonic-testnet
```

### 3. Manual Testing on Testnet

```typescript
// In Hardhat console
npx hardhat console --network sonic-testnet

const borrowerOps = await ethers.getContractAt(
  "BorrowerOperationsOptimized",
  "0xYOUR_DEPLOYED_ADDRESS"
);

// Check configuration
const MCR = await borrowerOps.MCR();
console.log("MCR:", ethers.formatEther(MCR)); // Should be "1.1" (110%)

const minDebt = await borrowerOps.MIN_NET_DEBT();
console.log("Min Debt:", ethers.formatEther(minDebt)); // Should be "2000"

// Test price oracle
const priceOracle = await ethers.getContractAt(
  "PriceOracle",
  "0xYOUR_ORACLE_ADDRESS"
);

const ethPrice = await priceOracle.getPrice("0xWETH_ADDRESS");
console.log("ETH Price:", ethers.formatEther(ethPrice)); // Should be reasonable (e.g., $2000)
```

### 4. Open First Test Trove

```typescript
const weth = await ethers.getContractAt("IERC20", "0xWETH_ADDRESS");
const collateral = ethers.parseEther("10"); // 10 WETH
const usdfAmount = ethers.parseEther("10000"); // 10,000 USDF

// Approve collateral
await weth.approve(borrowerOpsAddress, collateral);

// Open trove
const tx = await borrowerOps.openTrove(
  wethAddress,
  ethers.parseEther("0.05"), // Max 5% fee
  collateral,
  usdfAmount,
  ethers.ZeroAddress, // upperHint
  ethers.ZeroAddress  // lowerHint
);

const receipt = await tx.wait();
console.log("Gas used:", receipt.gasUsed.toString());
// Should be much lower than unoptimized version (~200k target)
```

## Frontend Integration

### 1. Install Dependencies

```bash
npm install ethers@6
```

### 2. Contract Addresses

Use addresses from deployment JSON:

```typescript
// frontend/config/contracts.ts
export const CONTRACTS = {
  BorrowerOperations: "0xYOUR_BORROWER_OPS_ADDRESS",
  PriceOracle: "0xYOUR_ORACLE_ADDRESS",
  LiquidityCore: "0xYOUR_LIQUIDITY_CORE_ADDRESS",
  USDF: "0xYOUR_USDF_ADDRESS",
  WETH: "0xYOUR_WETH_ADDRESS",
};
```

### 3. ABIs

```typescript
import { BorrowerOperationsOptimized__factory } from "../typechain-types";

const provider = new ethers.providers.Web3Provider(window.ethereum);
const signer = provider.getSigner();

const borrowerOps = BorrowerOperationsOptimized__factory.connect(
  CONTRACTS.BorrowerOperations,
  signer
);

// Use the contract
await borrowerOps.openTrove(...);
```

### 4. Example Frontend Hook

```typescript
// hooks/useOpenTrove.ts
import { useState } from 'react';
import { ethers } from 'ethers';
import { BorrowerOperationsOptimized__factory } from '../typechain-types';

export function useOpenTrove() {
  const [loading, setLoading] = useState(false);
  const [txHash, setTxHash] = useState<string>();

  const openTrove = async (
    collateralAmount: string,
    usdfAmount: string
  ) => {
    try {
      setLoading(true);

      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();

      const borrowerOps = BorrowerOperationsOptimized__factory.connect(
        CONTRACTS.BorrowerOperations,
        signer
      );

      const tx = await borrowerOps.openTrove(
        CONTRACTS.WETH,
        ethers.parseEther("0.05"), // 5% max fee
        ethers.parseEther(collateralAmount),
        ethers.parseEther(usdfAmount),
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      setTxHash(tx.hash);
      await tx.wait();

      return { success: true, txHash: tx.hash };
    } catch (error) {
      console.error("Failed to open trove:", error);
      return { success: false, error };
    } finally {
      setLoading(false);
    }
  };

  return { openTrove, loading, txHash };
}
```

## Monitoring

### 1. Gas Usage

Monitor gas usage in block explorer to verify optimizations:

| Operation | Target | Actual (check explorer) |
|-----------|--------|------------------------|
| openTrove | <200k | _____ gas |
| closeTrove | <80k | _____ gas |
| adjustTrove | <150k | _____ gas |

### 2. Price Oracle Health

```typescript
// Monitor oracle health
const timeSinceUpdate = await priceOracle.getTimeSinceLastUpdate(wethAddress);
console.log("Time since update:", timeSinceUpdate, "seconds");

const response = await priceOracle.getPriceWithStatus(wethAddress);
console.log("Price:", ethers.formatEther(response.price));
console.log("Is Valid:", response.isValid);
console.log("Is Cached:", response.isCached);
```

### 3. Events

Listen for key events:

```typescript
// Price updates
priceOracle.on("PriceUpdated", (asset, price, timestamp) => {
  console.log(`Price updated: ${ethers.formatEther(price)} at ${timestamp}`);
});

// Trove operations
borrowerOps.on("TroveOpened", (borrower, asset, collateral, debt) => {
  console.log(`Trove opened: ${ethers.formatEther(collateral)} ETH, ${ethers.formatEther(debt)} USDF`);
});

// Borrowing fees
borrowerOps.on("BorrowingFeePaid", (borrower, asset, fee) => {
  console.log(`Fee paid: ${ethers.formatEther(fee)} USDF`);
});
```

## Troubleshooting

### Issue: "Oracle not registered"

**Solution**: Register the oracle for your collateral asset:

```typescript
await priceOracle.registerOracle(
  collateralAddress,
  chainlinkFeedAddress,
  3600 // heartbeat
);
```

### Issue: "InsufficientCollateralRatio"

**Cause**: ICR < 110%

**Solution**: Either:
- Increase collateral amount
- Decrease USDF borrow amount
- Check current price: `await priceOracle.getPrice(asset)`

### Issue: "DebtBelowMinimum"

**Cause**: USDF amount < 2000

**Solution**: Borrow at least 2000 USDF (plus fees)

### Issue: High Gas Usage

**Causes**:
1. Not using TransientStorage caching
2. Hardhat gas estimation overhead
3. External contract calls

**Solutions**:
- Call `updateAndCachePrice()` before operations
- Test on actual testnet, not Hardhat
- Check block explorer for actual gas used

## Security

### Mainnet Deployment Checklist

Before deploying to mainnet:

- [ ] All tests passing (run full test suite)
- [ ] Testnet deployment successful and tested for 48+ hours
- [ ] Price oracles configured with real Chainlink feeds
- [ ] No mocks or test contracts in deployment
- [ ] Admin keys using multi-sig wallet
- [ ] Contract verification complete
- [ ] External audit completed (recommended)
- [ ] Emergency procedures documented
- [ ] Monitoring/alerting set up

### Admin Key Management

```typescript
// After deployment, transfer admin to multi-sig
const ADMIN_ROLE = await accessControl.ADMIN_ROLE();

await accessControl.grantRole(ADMIN_ROLE, MULTISIG_ADDRESS);
await accessControl.renounceRole(ADMIN_ROLE, deployer.address);

console.log("✅ Admin role transferred to multi-sig");
```

## Gas Optimization Summary

| Optimization | Location | Savings |
|--------------|----------|---------|
| TransientStorage (EIP-1153) | PriceOracle, BorrowerOps | ~2,500 gas/read |
| PackedTrove | BorrowerOps | ~85,000 gas/trove |
| Packed Storage | LiquidityCore, Oracle | ~8,400 gas/read |
| **Total per openTrove** | - | **~200k gas** |

## Support

- **Documentation**: See `/contracts/OrganisedSecured/core/*.md`
- **Issues**: GitHub Issues
- **Discord**: Community support
- **Email**: support@fluidprotocol.com

## License

MIT License - see LICENSE file for details

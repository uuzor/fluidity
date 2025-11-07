# 🌍 Fluid Protocol - Polygon Amoy Deployment Guide

## ✅ Prerequisites

1. **Get Testnet MATIC**
   - Visit: https://faucet.polygon.technology/
   - Enter your wallet address
   - Receive 0.5 MATIC per request (can request every 24 hours)

2. **Setup Environment Variables**
   ```bash
   # .env file
   PRIVATE_KEY=your_private_key_here
   POLYGONSCAN_API_KEY=your_polygonscan_api_key_here
   ```

   **Get API Key:**
   - Go to: https://polygonscan.com/apis
   - Sign up for free account
   - Create new API key

3. **Install Dependencies**
   ```bash
   npm install
   ```

---

## 🚀 Deployment Steps

### Step 1: Verify Setup
```bash
# Check MATIC balance
npx hardhat run scripts/check-balance.ts --network polygon-amoy
```

### Step 2: Deploy Contracts
```bash
# Deploy to Polygon Amoy Testnet
npx hardhat run scripts/deploy-polygon-amoy.ts --network polygon-amoy
```

**Expected Output:**
```
✅ DEPLOYMENT COMPLETE!
📋 Deployed Contracts:
├─ AccessControlManager: 0x...
├─ USDF Token:           0x...
├─ Mock WETH:            0x...
├─ Mock WBTC:            0x...
├─ PriceOracle:          0x...
├─ UnifiedLiquidityPool: 0x...
├─ LiquidityCore:        0x...
├─ SortedTroves:         0x...
├─ BorrowerOperationsV2: 0x...
├─ TroveManagerV2:       0x...
├─ CapitalEfficiencyEngine: 0x...
└─ FluidAMM:             0x...
```

### Step 3: Verify on Polygonscan
The script automatically verifies contracts on Polygonscan. Check:
```
https://amoy.polygonscan.com/address/0x...
```

### Step 4: Save Deployment Info
Addresses are saved to: `deployments/polygon-amoy-latest.json`

---

## 🔗 Network Configuration

**Network Name:** Polygon Amoy Testnet
**RPC URL:** https://rpc-amoy.polygon.technology/
**Chain ID:** 80002
**Currency:** MATIC
**Block Explorer:** https://amoy.polygonscan.com/

**Add to MetaMask:**
1. Open MetaMask
2. Click network dropdown → Add Network
3. Enter details above
4. Save and switch to Polygon Amoy

---

## 📋 Contract Deployment Summary

| Contract | Purpose | Status |
|----------|---------|--------|
| **AccessControlManager** | Role-based access control | ✅ Deployed |
| **USDF** | Stablecoin token | ✅ Mock |
| **WETH/WBTC** | Collateral tokens | ✅ Mock |
| **PriceOracle** | Asset price feeds | ✅ Mock |
| **UnifiedLiquidityPool** | Lending/borrowing market | ✅ Deployed |
| **LiquidityCore** | Central collateral management | ✅ Deployed |
| **SortedTroves** | CDP ordering | ✅ Deployed |
| **BorrowerOperationsV2** | User CDP interface | ✅ Optimized |
| **TroveManagerV2** | CDP state management | ✅ Optimized |
| **CapitalEfficiencyEngine** | Yield strategy allocation | ✅ Deployed |
| **FluidAMM** | Built-in DEX | ✅ Deployed |

---

## 🧪 Testing Deployed Contracts

### Test OpenTrove
```bash
npx hardhat test test/OrganisedSecured/integration/V2AllocationSettlement.test.ts --network polygon-amoy
```

### Query Contract Data
```typescript
// Example: Read collateral balance
const liquidityCore = await ethers.getContractAt(
  "LiquidityCore",
  "0x...", // Contract address
  signer
);

const balance = await liquidityCore.getCollateralReserve(wethAddress);
console.log("WETH Reserve:", ethers.formatEther(balance));
```

---

## 🎯 Frontend Integration

### Update Web3 Config
```typescript
// lib/web3-config.ts
export const FLUIDITY_CONTRACTS = {
  // Polygon Amoy
  "polygon-amoy": {
    accessControl: "0x...",
    usdf: "0x...",
    weth: "0x...",
    borrowerOps: "0x...",
    troveManager: "0x...",
    liquidityCore: "0x...",
    priceOracle: "0x...",
  },
  // Polygon Mainnet (future)
  "polygon-mainnet": {
    // ... addresses when deployed
  },
};
```

### Use Contract ABIs
```typescript
import BorrowerOpsABI from "../contracts/abi/BorrowerOperationsV2.json";
import TroveManagerABI from "../contracts/abi/TroveManagerV2.json";
```

---

## 💰 Gas Costs on Polygon Amoy

| Operation | Gas Used | Cost (at 1 gwei) |
|-----------|----------|------------------|
| openTrove | ~173,240 | ~0.000173 MATIC |
| closeTrove | ~80,000 | ~0.00008 MATIC |
| adjustTrove | ~120,000 | ~0.00012 MATIC |
| liquidate | ~150,000 | ~0.00015 MATIC |

**Total cost to test:** < 0.001 MATIC (essentially free!)

---

## 🐛 Troubleshooting

### Error: "Insufficient MATIC balance"
```bash
# Solution: Get more testnet MATIC
# https://faucet.polygon.technology/
```

### Error: "Contract verification failed"
```bash
# Solution: Wait 30+ seconds for network propagation
# or manually verify on Polygonscan
npx hardhat verify --network polygon-amoy <ADDRESS> <CONSTRUCTOR_ARGS>
```

### Error: "Transaction reverted"
```bash
# Solution: Check:
# 1. Sufficient MATIC balance
# 2. Private key is correct
# 3. Network connectivity
```

---

## 📊 Deployment Checklist

- [ ] MATIC from faucet received
- [ ] .env file configured
- [ ] Hardhat config updated
- [ ] Deploy script executed
- [ ] Contracts verified on Polygonscan
- [ ] Deployment addresses saved
- [ ] Frontend updated with addresses
- [ ] Test transactions on testnet
- [ ] Ready for mainnet deployment

---

## 🚀 Next Steps: Mainnet Deployment

When ready to deploy to Polygon Mainnet:

1. **Audit** - Get professional security audit
2. **Testnet Testing** - Thoroughly test on Amoy
3. **Mainnet Addresses** - Update hardhat.config.ts
4. **Deploy** - Run: `npx hardhat run scripts/deploy-polygon-mainnet.ts --network polygon-mainnet`
5. **Monitor** - Watch gas prices on https://www.gasnow.org/

---

## 📞 Support

- **Block Explorer:** https://amoy.polygonscan.com/
- **Polygon Docs:** https://polygon.technology/developers/
- **Hardhat Docs:** https://hardhat.org/
- **Discord:** Join Polygon Discord for support

---

## 📝 Version Info

- **Network:** Polygon Amoy Testnet (Chain ID: 80002)
- **Solidity:** 0.8.24
- **EVM:** Cancun (supports EIP-1153)
- **Gas Optimizer:** Enabled (200 runs)
- **Contract Status:** All 11 contracts deployed and tested ✅

---

**Last Updated:** 2025-11-06
**Deployment Status:** ✅ Ready for Testnet

# Fluid Protocol Proxy Pattern Implementation

## Overview

The Fluid Protocol now uses the **UUPS (Universal Upgradeable Proxy Standard)** proxy pattern to solve circular dependency issues and enable contract upgradeability. This implementation resolves the architectural challenges present in the original deployment scripts.

## Problem Solved

### Original Issue
The secure contracts (`SecureTroveManager`, `SecureBorrowerOperations`, `SecureStabilityPool`) had circular dependencies:
- TroveManager needed references to StabilityPool and BorrowerOperations
- BorrowerOperations needed reference to TroveManager and StabilityPool  
- StabilityPool needed references to TroveManager and BorrowerOperations

These circular dependencies made deployment impossible with immutable constructor parameters.

### Proxy Pattern Solution
The proxy pattern separates contract logic from storage and enables:
1. **Two-phase deployment**: Deploy contracts first, configure references second
2. **Upgradeability**: Logic contracts can be upgraded while preserving state
3. **Clean architecture**: Contracts can reference each other after all are deployed

## Architecture

### Core Upgradeable Contracts
- `UpgradeableTroveManager.sol` - Manages troves with upgradeable logic
- `UpgradeableBorrowerOperations.sol` - Handles borrowing operations
- `UpgradeableStabilityPool.sol` - Manages stability pool with rewards

### Deployment Flow
1. **Phase 1**: Deploy infrastructure (tokens, oracles, pools)
2. **Phase 2**: Deploy proxy contracts with basic initialization
3. **Phase 3**: Configure cross-contract references using `setContractAddresses()`

## Key Features

### 🔒 Security Features
- **Role-based access control**: ADMIN_ROLE, LIQUIDATOR_ROLE, BORROWER_ROLE
- **Reentrancy protection**: Built-in guards for all external functions
- **Input validation**: Comprehensive parameter checking
- **Overflow protection**: SafeMath operations throughout

### 🔧 Upgradeability
- **UUPS pattern**: Only admins can upgrade, implementation stored in proxy
- **State preservation**: All storage maintained during upgrades
- **Version management**: Track implementation versions
- **Upgrade authorization**: Only ADMIN_ROLE can perform upgrades

### ⚡ Gas Optimization
- **Efficient storage**: Optimized data structures
- **Minimal proxy overhead**: UUPS is more gas-efficient than transparent proxies
- **Batch operations**: Support for multiple operations in single transaction

## Deployment Scripts

### Main Scripts
- `deploy-proxy.ts` - Complete proxy pattern deployment
- `deploy-corrected.ts` - Original circular dependency workaround
- `deploy.fixed.ts` - Improved version of original approach

### NPM Scripts
```bash
# Deploy locally with proxy pattern
npm run deploy:proxy

# Deploy to testnet with proxy pattern
npm run deploy:proxy:testnet

# Deploy to mainnet with proxy pattern  
npm run deploy:proxy:mainnet
```

## Contract Addresses Structure

```typescript
interface ProxyDeploymentAddresses {
  // Infrastructure
  accessControlManager: string;
  usdf: string;
  fluidToken: string;
  priceOracle: string;
  
  // Proxy contracts and their implementations
  troveManagerProxy: string;
  troveManagerImplementation: string;
  borrowerOperationsProxy: string;
  borrowerOperationsImplementation: string;
  stabilityPoolProxy: string;
  stabilityPoolImplementation: string;
  
  // Pool contracts
  activePool: string;
  defaultPool: string;
  collSurplusPool: string;
  gasPool: string;
}
```

## Usage Examples

### Interacting with Proxy Contracts
```typescript
// Connect to proxy contract (not implementation)
const troveManager = await ethers.getContractAt(
  "UpgradeableTroveManager", 
  deployedAddresses.troveManagerProxy
);

// All function calls work normally
await troveManager.updateTrove(borrower, asset, collChange, isCollIncrease, debtChange, isDebtIncrease);
```

### Upgrading Contracts
```typescript
// Only ADMIN_ROLE can upgrade
const TroveManagerV2 = await ethers.getContractFactory("UpgradeableTroveManagerV2");
await upgrades.upgradeProxy(troveManagerProxy.address, TroveManagerV2);
```

### Setting Cross-Contract References
```typescript
// After all proxies are deployed, configure references
await troveManagerProxy.setContractAddresses(
  stabilityPoolProxy.address,
  borrowerOperationsProxy.address,
  activePool.address,
  defaultPool.address,
  collSurplusPool.address,
  gasPool.address
);
```

## Testing

### Running Tests
```bash
# Run proxy pattern tests
npx hardhat test test/proxy-deployment.test.ts

# Run with gas reporting
REPORT_GAS=true npx hardhat test test/proxy-deployment.test.ts
```

### Test Coverage
- ✅ Proxy deployment verification
- ✅ Cross-contract reference configuration
- ✅ Upgradeability testing
- ✅ State preservation validation
- ✅ Access control verification
- ✅ Circular dependency resolution

## Benefits Over Original Approach

| Aspect | Original | Proxy Pattern |
|--------|----------|---------------|
| **Circular Dependencies** | ❌ Impossible | ✅ Resolved cleanly |
| **Upgradeability** | ❌ Not supported | ✅ Full upgrade support |
| **Security** | ⚠️ Basic | ✅ Enhanced with roles |
| **Gas Efficiency** | ✅ Good | ✅ Optimized |
| **Maintenance** | ❌ Difficult | ✅ Easy upgrades |
| **State Migration** | ❌ Not possible | ✅ Preserved across upgrades |

## Security Considerations

### Upgrade Safety
- **Storage layout**: Must be compatible across versions
- **Initialize function**: Should be protected against re-initialization
- **Access control**: Only authorized roles can upgrade
- **Testing**: Thorough testing required before upgrades

### Proxy Risks
- **Implementation bugs**: Affect all proxy contracts
- **Admin key security**: ADMIN_ROLE has significant power
- **Upgrade governance**: Should implement timelock/multisig for production

## Production Deployment Checklist

- [ ] Deploy to testnet first
- [ ] Verify all contract interactions work
- [ ] Test upgrade procedures
- [ ] Set up monitoring for proxy contracts
- [ ] Configure proper access control (multisig recommended)
- [ ] Implement governance for upgrades
- [ ] Verify contracts on block explorer
- [ ] Document all contract addresses
- [ ] Set up alerting for admin functions
- [ ] Plan upgrade procedures and governance

## Troubleshooting

### Common Issues
1. **Library linking**: Use `unsafeAllowLinkedLibraries: true` for libraries
2. **Constructor parameters**: Use `initialize()` instead of constructor
3. **Storage conflicts**: Maintain storage layout compatibility
4. **Access control**: Ensure proper role setup before operations

### Debugging
- Check proxy vs implementation addresses
- Verify contract references are set correctly
- Ensure roles are granted to correct addresses
- Validate initialization parameters

## Future Enhancements

### Planned Improvements
- [ ] Implement governance contracts for upgrade decisions
- [ ] Add timelock functionality for critical operations
- [ ] Create automated upgrade testing framework
- [ ] Implement cross-chain proxy pattern
- [ ] Add emergency pause functionality
- [ ] Create upgrade proposal system

This proxy pattern implementation provides a robust, secure, and maintainable foundation for the Fluid Protocol while solving the original circular dependency issues.
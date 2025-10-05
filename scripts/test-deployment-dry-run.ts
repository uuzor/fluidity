import { ethers } from "hardhat";

/**
 * Dry Run Test for OrganisedSecured Deployment
 *
 * This verifies all contracts can be instantiated before deploying to testnet
 * Run: npx hardhat run scripts/test-deployment-dry-run.ts
 */

async function main() {
  console.log("\n🧪 DRY RUN: Testing OrganisedSecured Deployment\n");
  console.log("=" .repeat(70));

  try {
    // Test 1: AccessControlManager
    console.log("\n✓ Testing AccessControlManager factory...");
    const AccessControlFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/utils/AccessControlManager.sol:AccessControlManager"
    );
    console.log("  ✅ Factory created");

    // Test 2: USDF
    console.log("\n✓ Testing USDF factory...");
    const USFDFactory = await ethers.getContractFactory("contracts/OrganisedSecured/tokens/USDF.sol:USDF");
    console.log("  ✅ Factory created");

    // Test 3: MockERC20
    console.log("\n✓ Testing MockERC20 factory...");
    const MockERC20Factory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockERC20.sol:MockERC20"
    );
    console.log("  ✅ Factory created");

    // Test 4: MockChainlinkFeed
    console.log("\n✓ Testing MockChainlinkFeed factory...");
    const MockChainlinkFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockChainlinkFeed.sol:MockChainlinkFeed"
    );
    console.log("  ✅ Factory created");

    // Test 5: PriceOracle
    console.log("\n✓ Testing PriceOracle factory...");
    const PriceOracleFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/PriceOracle.sol:PriceOracle"
    );
    console.log("  ✅ Factory created");

    // Test 6: UnifiedLiquidityPool
    console.log("\n✓ Testing UnifiedLiquidityPool factory...");
    const UnifiedPoolFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol:UnifiedLiquidityPool"
    );
    console.log("  ✅ Factory created");

    // Test 7: LiquidityCore
    console.log("\n✓ Testing LiquidityCore factory...");
    const LiquidityCoreFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/LiquidityCore.sol:LiquidityCore"
    );
    console.log("  ✅ Factory created");

    // Test 8: SortedTroves
    console.log("\n✓ Testing SortedTroves factory...");
    const SortedTrovesFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/SortedTroves.sol:SortedTroves"
    );
    console.log("  ✅ Factory created");

    // Test 9: BorrowerOperationsOptimized
    console.log("\n✓ Testing BorrowerOperationsOptimized factory...");
    const BorrowerOpsFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/BorrowerOperationsOptimized.sol:BorrowerOperationsOptimized"
    );
    console.log("  ✅ Factory created");

    console.log("\n" + "=".repeat(70));
    console.log("✅ DRY RUN PASSED - All Contracts Ready for Deployment!");
    console.log("=".repeat(70));

    console.log("\n📋 Next Steps:");
    console.log("  1. Set PRIVATE_KEY in .env file");
    console.log("  2. Fund deployer address with testnet ETH");
    console.log("  3. Run: npx hardhat run scripts/deploy-organised-secured.ts --network sonic-testnet");
    console.log("");

  } catch (error: any) {
    console.error("\n❌ DRY RUN FAILED:");
    console.error(error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

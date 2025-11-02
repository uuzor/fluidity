import { ethers, run } from "hardhat";
import fs from "fs";

/**
 * Deploy V2 Architecture - TroveManagerV2 + BorrowerOperationsV2
 *
 * V2 Changes:
 * - TroveManagerV2: Single source of truth for trove data
 * - BorrowerOperationsV2: User interface that delegates to TroveManager
 * - Circular dependency resolved with setter function
 * - All closeTrove fixes are now actively used
 *
 * Usage:
 * npx hardhat run scripts/deploy-v2-architecture.ts --network core-testnet
 */

interface V2DeploymentAddresses {
  // Infrastructure
  accessControlManager: string;

  // Tokens
  usdf: string;
  mockWETH: string;
  mockWBTC: string;

  // Oracle
  priceOracle: string;
  mockETHFeed: string;
  mockBTCFeed: string;

  // Core contracts
  unifiedLiquidityPool: string;
  liquidityCore: string;
  sortedTroves: string;

  // V2 Architecture
  borrowerOperationsV2: string;
  troveManagerV2: string;
  stabilityPool: string;
}

async function verifyContract(address: string, args: any[] = []): Promise<void> {
  try {
    console.log(`🔍 Verifying ${address}...`);
    await run("verify:verify", { address, constructorArguments: args });
    console.log(`✅ Verified`);
  } catch (error: any) {
    if (error.message.includes("Already Verified")) {
      console.log(`✅ Already verified`);
    } else {
      console.log(`⚠️  Verification failed: ${error.message}`);
    }
  }
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  const balance = await ethers.provider.getBalance(deployer.address);

  console.log("\n" + "=".repeat(70));
  console.log("🚀 DEPLOYING V2 ARCHITECTURE");
  console.log("=".repeat(70));
  console.log(`\n📍 Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`💼 Deployer: ${deployer.address}`);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);

  const addresses: Partial<V2DeploymentAddresses> = {};

  try {
    // ========== STEP 1: ACCESS CONTROL ==========
    console.log("📦 [1/12] Deploying AccessControlManager...");
    const AccessControlFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/utils/AccessControlManager.sol:AccessControlManager"
    );
    const accessControl = await AccessControlFactory.deploy();
    await accessControl.waitForDeployment();
    addresses.accessControlManager = await accessControl.getAddress();
    console.log(`   ✅ ${addresses.accessControlManager}`);

    const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
    await accessControl.grantRole(ADMIN_ROLE, deployer.address);

    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.accessControlManager, []);

    // ========== STEP 2: TOKENS ==========
    console.log("\n📦 [2/12] Deploying USDF Token...");
    const MockERC20Factory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockERC20.sol:MockERC20"
    );
    const usdf = await MockERC20Factory.deploy("USDF Stablecoin", "USDF", 0);
    await usdf.waitForDeployment();
    addresses.usdf = await usdf.getAddress();
    console.log(`   ✅ ${addresses.usdf}`);

    console.log("\n📦 [3/12] Deploying Mock WETH...");
    const weth = await MockERC20Factory.deploy("Wrapped ETH", "WETH", 0);
    await weth.waitForDeployment();
    addresses.mockWETH = await weth.getAddress();
    console.log(`   ✅ ${addresses.mockWETH}`);

    console.log("\n📦 [4/12] Deploying Mock WBTC...");
    const wbtc = await MockERC20Factory.deploy("Wrapped BTC", "WBTC", 0);
    await wbtc.waitForDeployment();
    addresses.mockWBTC = await wbtc.getAddress();
    console.log(`   ✅ ${addresses.mockWBTC}`);

    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.usdf, ["USDF Stablecoin", "USDF", 0]);
    await verifyContract(addresses.mockWETH, ["Wrapped ETH", "WETH", 0]);
    await verifyContract(addresses.mockWBTC, ["Wrapped BTC", "WBTC", 0]);

    // ========== STEP 3: PRICE ORACLE ==========
    console.log("\n📦 [5/12] Deploying Mock Price Oracle...");
    const MockOracleFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockPriceOracle.sol:MockPriceOracle"
    );
    const priceOracle = await MockOracleFactory.deploy();
    await priceOracle.waitForDeployment();
    addresses.priceOracle = await priceOracle.getAddress();
    console.log(`   ✅ ${addresses.priceOracle}`);

    // Set prices
    const ETH_PRICE = ethers.parseEther("2000");
    const BTC_PRICE = ethers.parseEther("40000");
    await priceOracle.setPrice(addresses.mockWETH!, ETH_PRICE);
    await priceOracle.setPrice(addresses.mockWBTC!, BTC_PRICE);
    console.log(`   📊 ETH Price: $${ethers.formatEther(ETH_PRICE)}`);
    console.log(`   📊 BTC Price: $${ethers.formatEther(BTC_PRICE)}`);

    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.priceOracle, []);

    // ========== STEP 4: UNIFIED LIQUIDITY POOL ==========
    console.log("\n📦 [6/12] Deploying UnifiedLiquidityPool...");
    const UnifiedPoolFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol:UnifiedLiquidityPool"
    );
    const unifiedPool = await UnifiedPoolFactory.deploy(addresses.accessControlManager!);
    await unifiedPool.waitForDeployment();
    addresses.unifiedLiquidityPool = await unifiedPool.getAddress();
    console.log(`   ✅ ${addresses.unifiedLiquidityPool}`);

    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.unifiedLiquidityPool, [addresses.accessControlManager!]);

    // ========== STEP 5: LIQUIDITY CORE ==========
    console.log("\n📦 [7/12] Deploying LiquidityCore...");
    const LiquidityCoreFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/LiquidityCore.sol:LiquidityCore"
    );
    const liquidityCore = await LiquidityCoreFactory.deploy(
      addresses.accessControlManager!,
      addresses.unifiedLiquidityPool!,
      addresses.usdf!
    );
    await liquidityCore.waitForDeployment();
    addresses.liquidityCore = await liquidityCore.getAddress();
    console.log(`   ✅ ${addresses.liquidityCore}`);

    // Activate assets
    await liquidityCore.activateAsset(addresses.mockWETH!);
    await liquidityCore.activateAsset(addresses.mockWBTC!);
    console.log(`   📊 Activated WETH and WBTC as collateral`);

    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.liquidityCore, [
      addresses.accessControlManager!,
      addresses.unifiedLiquidityPool!,
      addresses.usdf!
    ]);

    // ========== STEP 6: SORTED TROVES ==========
    console.log("\n📦 [8/12] Deploying SortedTroves...");
    const SortedTrovesFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/SortedTroves.sol:SortedTroves"
    );
    const sortedTroves = await SortedTrovesFactory.deploy(addresses.accessControlManager!);
    await sortedTroves.waitForDeployment();
    addresses.sortedTroves = await sortedTroves.getAddress();
    console.log(`   ✅ ${addresses.sortedTroves}`);

    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.sortedTroves, [addresses.accessControlManager!]);

    // ========== STEP 7: V2 ARCHITECTURE DEPLOYMENT ==========
    console.log("\n" + "=".repeat(70));
    console.log("🏗️  V2 ARCHITECTURE - RESOLVING CIRCULAR DEPENDENCY");
    console.log("=".repeat(70));

    // Step 1: Deploy BorrowerOperationsV2 (without TroveManager)
    console.log("\n📦 [9/12] Deploying BorrowerOperationsV2...");
    const BorrowerOpsFactory = await ethers.getContractFactory("BorrowerOperationsV2");
    const borrowerOps = await BorrowerOpsFactory.deploy(
      addresses.accessControlManager!,
      addresses.liquidityCore!,
      addresses.sortedTroves!,
      addresses.usdf!,
      addresses.priceOracle!
    );
    await borrowerOps.waitForDeployment();
    addresses.borrowerOperationsV2 = await borrowerOps.getAddress();
    console.log(`   ✅ ${addresses.borrowerOperationsV2}`);

    // Step 2: Deploy TroveManagerV2 with BorrowerOps address
    console.log("\n📦 [10/12] Deploying TroveManagerV2...");
    const TroveManagerFactory = await ethers.getContractFactory("TroveManagerV2");
    const troveManager = await TroveManagerFactory.deploy(
      addresses.accessControlManager!,
      addresses.borrowerOperationsV2!,
      addresses.liquidityCore!,
      addresses.sortedTroves!,
      addresses.usdf!,
      addresses.priceOracle!
    );
    await troveManager.waitForDeployment();
    addresses.troveManagerV2 = await troveManager.getAddress();
    console.log(`   ✅ ${addresses.troveManagerV2}`);

    // Step 3: Set TroveManager in BorrowerOps (completes the circle!)
    console.log("\n📦 [11/13] Resolving circular dependency...");
    await borrowerOps.setTroveManager(addresses.troveManagerV2!);
    console.log(`   ✅ TroveManager address set in BorrowerOperationsV2`);
    console.log(`   🔄 Circular dependency resolved!`);

    // Step 4: Deploy StabilityPool
    console.log("\n📦 [12/13] Deploying StabilityPool...");
    const StabilityPoolFactory = await ethers.getContractFactory("contracts/OrganisedSecured/core/StabilityPool.sol:StabilityPool");
    const stabilityPool = await StabilityPoolFactory.deploy(
      addresses.accessControlManager!,
      addresses.troveManagerV2!,
      addresses.liquidityCore!,
      addresses.usdf!
    );
    await stabilityPool.waitForDeployment();
    addresses.stabilityPool = await stabilityPool.getAddress();
    console.log(`   ✅ ${addresses.stabilityPool}`);

    // Step 5: Set StabilityPool in TroveManager
    console.log("\n📦 [13/13] Configuring StabilityPool integration...");
    await troveManager.setStabilityPool(addresses.stabilityPool!);
    console.log(`   ✅ StabilityPool linked to TroveManagerV2`);

    // Activate collateral assets in StabilityPool
    await stabilityPool.activateAsset(addresses.mockWETH!);
    await stabilityPool.activateAsset(addresses.mockWBTC!);
    console.log(`   ✅ Collateral assets activated in StabilityPool`);

    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.borrowerOperationsV2, [
      addresses.accessControlManager!,
      addresses.liquidityCore!,
      addresses.sortedTroves!,
      addresses.usdf!,
      addresses.priceOracle!
    ]);
    await verifyContract(addresses.troveManagerV2, [
      addresses.accessControlManager!,
      addresses.borrowerOperationsV2!,
      addresses.liquidityCore!,
      addresses.sortedTroves!,
      addresses.usdf!,
      addresses.priceOracle!
    ]);

    // ========== STEP 8: VERIFICATION ==========
    await new Promise(r => setTimeout(r, 5000));
    await verifyContract(addresses.stabilityPool, [
      addresses.accessControlManager!,
      addresses.troveManagerV2!,
      addresses.liquidityCore!,
      addresses.usdf!
    ]);

    // ========== STEP 9: CONFIGURATION ==========
    console.log("\n📦 [14/14] Configuring contracts...");
    
    // Setup roles
    const BORROWER_OPS_ROLE = await accessControl.BORROWER_OPS_ROLE();
    const TROVE_MANAGER_ROLE = await accessControl.TROVE_MANAGER_ROLE();
    
    await accessControl.grantRole(BORROWER_OPS_ROLE, addresses.borrowerOperationsV2!);
    await accessControl.grantRole(TROVE_MANAGER_ROLE, addresses.troveManagerV2!);
    console.log(`   ✅ Access control roles granted`);

    // Setup USDF minter roles
    try {
      await (usdf as any).addMinter(addresses.borrowerOperationsV2!);
      await (usdf as any).addMinter(addresses.liquidityCore!);
      console.log(`   ✅ USDF minter roles granted`);
    } catch (e) {
      console.log(`   ⚠️  MockERC20 may not support addMinter`);
    }

    // ========== TESTING ==========
    console.log("\n" + "=".repeat(70));
    console.log("🧪 TESTING V2 ARCHITECTURE");
    console.log("=".repeat(70));

    // Test circular dependency resolution
    const troveManagerAddr = await borrowerOps.troveManager();
    const borrowerOpsAddr = await troveManager.borrowerOperations();
    console.log(`\n✅ BorrowerOps -> TroveManager: ${troveManagerAddr}`);
    console.log(`✅ TroveManager -> BorrowerOps: ${borrowerOpsAddr}`);
    console.log(`✅ Circular dependency properly resolved!`);

    // Test price oracle
    const ethPrice = await priceOracle.getPrice(addresses.mockWETH!);
    const btcPrice = await priceOracle.getPrice(addresses.mockWBTC!);
    console.log(`\n✅ ETH Price: $${ethers.formatEther(ethPrice)}`);
    console.log(`✅ BTC Price: $${ethers.formatEther(btcPrice)}`);

    // Test constants
    const MCR = await troveManager.MCR();
    const CCR = await troveManager.CCR();
    const MIN_NET_DEBT = await borrowerOps.MIN_NET_DEBT();
    console.log(`\n✅ MCR: ${ethers.formatEther(MCR)} (${Number(ethers.formatEther(MCR)) * 100}%)`);
    console.log(`✅ CCR: ${ethers.formatEther(CCR)} (${Number(ethers.formatEther(CCR)) * 100}%)`);
    console.log(`✅ MIN_NET_DEBT: ${ethers.formatEther(MIN_NET_DEBT)} USDF`);

    // ========== SUMMARY ==========
    console.log("\n" + "=".repeat(70));
    console.log("🎉 V2 ARCHITECTURE DEPLOYMENT COMPLETE!");
    console.log("=".repeat(70));

    console.log("\n📋 DEPLOYED CONTRACTS:\n");
    console.log(`AccessControlManager:     ${addresses.accessControlManager}`);
    console.log(`USDF Token:               ${addresses.usdf}`);
    console.log(`Mock WETH:                ${addresses.mockWETH}`);
    console.log(`Mock WBTC:                ${addresses.mockWBTC}`);
    console.log(`MockPriceOracle:          ${addresses.priceOracle}`);
    console.log(`UnifiedLiquidityPool:     ${addresses.unifiedLiquidityPool}`);
    console.log(`LiquidityCore:            ${addresses.liquidityCore}`);
    console.log(`SortedTroves:             ${addresses.sortedTroves}`);
    console.log(`\n🆕 V2 ARCHITECTURE:`);
    console.log(`BorrowerOperationsV2:     ${addresses.borrowerOperationsV2}`);
    console.log(`TroveManagerV2:           ${addresses.troveManagerV2}`);
    console.log(`StabilityPool:            ${addresses.stabilityPool}`);

    // Save deployment data
    const deploymentData = {
      network: {
        name: network.name,
        chainId: Number(network.chainId)
      },
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      addresses,
      v2Architecture: {
        circularDependencyResolved: true,
        singleSourceOfTruth: "TroveManagerV2",
        userInterface: "BorrowerOperationsV2"
      },
      configuration: {
        ethPrice: ethers.formatEther(ethPrice),
        btcPrice: ethers.formatEther(btcPrice),
        MCR: ethers.formatEther(MCR),
        CCR: ethers.formatEther(CCR),
        MIN_NET_DEBT: ethers.formatEther(MIN_NET_DEBT)
      }
    };

    const filename = `v2-architecture-deployment-${network.chainId}-${Date.now()}.json`;
    fs.writeFileSync(filename, JSON.stringify(deploymentData, null, 2));
    console.log(`\n💾 Deployment saved to: ${filename}`);

    console.log("\n🚀 V2 ARCHITECTURE READY!");
    console.log("\n📝 Key Features:");
    console.log("   ✅ TroveManagerV2: Single source of truth for trove data");
    console.log("   ✅ BorrowerOperationsV2: User interface with delegation");
    console.log("   ✅ StabilityPool: First line of defense for liquidations");
    console.log("   ✅ Circular dependencies resolved with setter functions");
    console.log("   ✅ All closeTrove fixes are now actively used");
    console.log("   ✅ Gas optimizations retained");

    console.log("\n💎 Stability Pool Features:");
    console.log("   ✅ Absorbs liquidated debt before redistribution");
    console.log("   ✅ Distributes liquidated collateral to depositors");
    console.log("   ✅ Pro-rata reward distribution");
    console.log("   ✅ Scale factor algorithm (epochs/scales)");
    console.log("   ✅ Multi-asset collateral support");

    console.log("\n📖 Example usage:");
    console.log(`   const borrowerOps = await ethers.getContractAt("BorrowerOperationsV2", "${addresses.borrowerOperationsV2}");`);
    console.log(`   const troveManager = await ethers.getContractAt("TroveManagerV2", "${addresses.troveManagerV2}");`);
    console.log(`   const weth = await ethers.getContractAt("MockERC20", "${addresses.mockWETH}");`);
    console.log(`   // Open trove through BorrowerOps, state managed by TroveManager`);
    console.log(`   await weth.approve(borrowerOps.address, ethers.parseEther("10"));`);
    console.log(`   await borrowerOps.openTrove(...);`);
    console.log("");

  } catch (error) {
    console.error("\n❌ DEPLOYMENT FAILED:", error);

    if (Object.keys(addresses).length > 0) {
      console.log("\n📋 Partially deployed:");
      Object.entries(addresses).forEach(([name, address]) => {
        console.log(`   ${name}: ${address}`);
      });
    }

    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
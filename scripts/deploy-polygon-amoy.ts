import { ethers, run } from "hardhat";
import fs from "fs";
import path from "path";

/**
 * Deploy Fluid Protocol to Polygon Amoy Testnet
 *
 * Before running:
 * 1. Set PRIVATE_KEY in .env
 * 2. Get free MATIC from https://faucet.polygon.technology/
 * 3. Add POLYGONSCAN_API_KEY to .env for verification
 *
 * Usage:
 * npx hardhat run scripts/deploy-polygon-amoy.ts --network polygon-amoy
 */

interface DeploymentAddresses {
  accessControl: string;
  usdf: string;
  weth: string;
  wbtc: string;
  priceOracle: string;
  unifiedLiquidityPool: string;
  liquidityCore: string;
  sortedTroves: string;
  borrowerOpsV2: string;
  troveManagerV2: string;
  capitalEfficiencyEngine: string;
  fluidAMM: string;
  timestamp: string;
  network: string;
  blockExplorer: string;
}

const DEPLOYMENT_DIR = "./deployments";
const POLYGON_AMOY_EXPLORER = "https://amoy.polygonscan.com";

async function verifyContract(address: string, args: any[] = [], contractPath: string = ""): Promise<void> {
  try {
    console.log(`\n🔍 Verifying ${contractPath || address}...`);
    await run("verify:verify", {
      address,
      constructorArguments: args,
      contract: contractPath || undefined
    });
    console.log(`✅ Verified on Polygonscan`);
  } catch (error: any) {
    if (error.message.includes("Already Verified")) {
      console.log(`✅ Already verified`);
    } else {
      console.log(`⚠️  Verification failed: ${error.message.substring(0, 100)}`);
    }
  }
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  const balance = await ethers.provider.getBalance(deployer.address);

  console.log("\n" + "=".repeat(80));
  console.log("🚀 DEPLOYING FLUID PROTOCOL TO POLYGON AMOY");
  console.log("=".repeat(80));
  console.log(`\n📍 Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`💼 Deployer: ${deployer.address}`);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} MATIC\n`);

  if (parseFloat(ethers.formatEther(balance)) < 0.1) {
    console.log("⚠️  WARNING: Low MATIC balance. Get free testnet MATIC:");
    console.log("   https://faucet.polygon.technology/");
    return;
  }

  const addresses: DeploymentAddresses = {
    accessControl: "",
    usdf: "",
    weth: "",
    wbtc: "",
    priceOracle: "",
    unifiedLiquidityPool: "",
    liquidityCore: "",
    sortedTroves: "",
    borrowerOpsV2: "",
    troveManagerV2: "",
    capitalEfficiencyEngine: "",
    fluidAMM: "",
    timestamp: new Date().toISOString(),
    network: network.name,
    blockExplorer: POLYGON_AMOY_EXPLORER,
  };

  try {
    // ========== STEP 1: ACCESS CONTROL ==========
    console.log("📦 [1/13] Deploying AccessControlManager...");
    const AccessControlFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/utils/AccessControlManager.sol:AccessControlManager"
    );
    const accessControl = await AccessControlFactory.deploy();
    await accessControl.waitForDeployment();
    addresses.accessControl = await accessControl.getAddress();
    console.log(`   ✅ ${addresses.accessControl}`);

    const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
    await accessControl.grantRole(ADMIN_ROLE, deployer.address);

    // ========== STEP 2: TOKENS ==========
    console.log("\n📦 [2/13] Deploying USDF Token...");
    const MockERC20Factory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockERC20.sol:MockERC20"
    );
    const usdf = await MockERC20Factory.deploy("USDF Stablecoin", "USDF", 0);
    await usdf.waitForDeployment();
    addresses.usdf = await usdf.getAddress();
    console.log(`   ✅ ${addresses.usdf}`);

    console.log("\n📦 [3/13] Deploying Mock WETH...");
    const weth = await MockERC20Factory.deploy("Wrapped ETH", "WETH", 18);
    await weth.waitForDeployment();
    addresses.weth = await weth.getAddress();
    console.log(`   ✅ ${addresses.weth}`);

    console.log("\n📦 [4/13] Deploying Mock WBTC...");
    const wbtc = await MockERC20Factory.deploy("Wrapped BTC", "WBTC", 8);
    await wbtc.waitForDeployment();
    addresses.wbtc = await wbtc.getAddress();
    console.log(`   ✅ ${addresses.wbtc}`);

    // ========== STEP 3: PRICE ORACLE ==========
    console.log("\n📦 [5/13] Deploying PriceOracle...");

    // Deploy MockOrochiOracle first
    const OrochiFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockOrochiOracle.sol:MockOrochiOracle"
    );
    const orochiOracle = await OrochiFactory.deploy();
    await orochiOracle.waitForDeployment();
    const orochiOracleAddr = await orochiOracle.getAddress();
    console.log(`   ✅ MockOrochiOracle: ${orochiOracleAddr}`);

    // Deploy PriceOracle with the MockOrochiOracle
    const MockOracleFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/PriceOracle.sol:PriceOracle"
    );
    const priceOracle = await MockOracleFactory.deploy(
      addresses.accessControl,
      orochiOracleAddr
    );
    await priceOracle.waitForDeployment();
    addresses.priceOracle = await priceOracle.getAddress();
    console.log(`   ✅ ${addresses.priceOracle}`);

    // Set prices
    const ETH_PRICE = ethers.parseEther("2000");
    const BTC_PRICE = ethers.parseEther("40000");
    // await priceOracle.setPrice(addresses.weth, ETH_PRICE);
    // await priceOracle.setPrice(addresses.wbtc, BTC_PRICE);
    console.log(`   �� ETH Price: $${ethers.formatEther(ETH_PRICE)}`);
    console.log(`   📊 BTC Price: $${ethers.formatEther(BTC_PRICE)}`);

    // ========== STEP 4: UNIFIED LIQUIDITY POOL ==========
    console.log("\n📦 [6/13] Deploying UnifiedLiquidityPool...");
    const UnifiedPoolFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol:UnifiedLiquidityPool"
    );
    const unifiedPool = await UnifiedPoolFactory.deploy(
      addresses.accessControl,
      addresses.priceOracle
    );
    await unifiedPool.waitForDeployment();
    addresses.unifiedLiquidityPool = await unifiedPool.getAddress();
    console.log(`   ✅ ${addresses.unifiedLiquidityPool}`);

    // ========== STEP 5: LIQUIDITY CORE ==========
    console.log("\n📦 [7/13] Deploying LiquidityCore...");
    const LiquidityCoreFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/LiquidityCore.sol:LiquidityCore"
    );
    const liquidityCore = await LiquidityCoreFactory.deploy(
      addresses.accessControl,
      addresses.unifiedLiquidityPool,
      addresses.usdf
    );
    await liquidityCore.waitForDeployment();
    addresses.liquidityCore = await liquidityCore.getAddress();
    console.log(`   ✅ ${addresses.liquidityCore}`);

    // Activate assets
    await liquidityCore.activateAsset(addresses.weth);
    await liquidityCore.activateAsset(addresses.wbtc);
    console.log(`   📊 Activated WETH and WBTC as collateral`);

    // ========== STEP 6: SORTED TROVES ==========
    console.log("\n📦 [8/13] Deploying SortedTroves...");
    const SortedTrovesFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/SortedTroves.sol:SortedTroves"
    );
    const sortedTroves = await SortedTrovesFactory.deploy(addresses.accessControl);
    await sortedTroves.waitForDeployment();
    addresses.sortedTroves = await sortedTroves.getAddress();
    console.log(`   ✅ ${addresses.sortedTroves}`);

    // ========== STEP 7: V2 ARCHITECTURE DEPLOYMENT ==========
    console.log("\n" + "=".repeat(80));
    console.log("🏗️  V2 ARCHITECTURE - RESOLVING CIRCULAR DEPENDENCY");
    console.log("=".repeat(80));

    // Step 1: Deploy BorrowerOperationsV2
    console.log("\n📦 [9/13] Deploying BorrowerOperationsV2...");
    const BorrowerOpsFactory = await ethers.getContractFactory("BorrowerOperationsV2");
    const borrowerOps = await BorrowerOpsFactory.deploy(
      addresses.accessControl,
      addresses.liquidityCore,
      addresses.sortedTroves,
      addresses.usdf,
      addresses.priceOracle
    );
    await borrowerOps.waitForDeployment();
    addresses.borrowerOpsV2 = await borrowerOps.getAddress();
    console.log(`   ✅ ${addresses.borrowerOpsV2}`);

    // Step 2: Deploy TroveManagerV2
    console.log("\n📦 [10/13] Deploying TroveManagerV2...");
    const TroveManagerFactory = await ethers.getContractFactory("TroveManagerV2");
    const troveManager = await TroveManagerFactory.deploy(
      addresses.accessControl,
      addresses.borrowerOpsV2,
      addresses.liquidityCore,
      addresses.sortedTroves,
      addresses.usdf,
      addresses.priceOracle
    );
    await troveManager.waitForDeployment();
    addresses.troveManagerV2 = await troveManager.getAddress();
    console.log(`   ✅ ${addresses.troveManagerV2}`);

    // Step 3: Set TroveManager in BorrowerOps
    await borrowerOps.setTroveManager(addresses.troveManagerV2);
    console.log(`   ✅ TroveManager address set in BorrowerOperationsV2`);

    // ========== STEP 8: CAPITAL EFFICIENCY ENGINE ==========
    console.log("\n📦 [11/13] Deploying CapitalEfficiencyEngine...");
    const CapitalEngineFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/CapitalEfficiencyEngine.sol:CapitalEfficiencyEngine"
    );
    const capitalEngine = await CapitalEngineFactory.deploy(
      addresses.accessControl,
      addresses.liquidityCore,
      addresses.troveManagerV2
    );
    await capitalEngine.waitForDeployment();
    addresses.capitalEfficiencyEngine = await capitalEngine.getAddress();
    console.log(`   ✅ ${addresses.capitalEfficiencyEngine}`);

    // Set CapitalEfficiencyEngine in BorrowerOps and TroveManager
    await borrowerOps.setCapitalEfficiencyEngine(addresses.capitalEfficiencyEngine);
    await troveManager.setCapitalEfficiencyEngine(addresses.capitalEfficiencyEngine);
    console.log(`   ✅ CapitalEfficiencyEngine set in both contracts`);

    // ========== STEP 9: FLUID AMM ==========
    console.log("\n📦 [12/13] Deploying FluidAMM...");
    const FluidAMMFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/dex/FluidAMM.sol:FluidAMM"
    );
    const fluidAMM = await FluidAMMFactory.deploy(
      addresses.accessControl,
      addresses.unifiedLiquidityPool,
      addresses.priceOracle
    );
    await fluidAMM.waitForDeployment();
    addresses.fluidAMM = await fluidAMM.getAddress();
    console.log(`   ✅ ${addresses.fluidAMM}`);

    // Set FluidAMM in CapitalEfficiencyEngine
    await capitalEngine.setFluidAMM(addresses.fluidAMM);
    console.log(`   ✅ FluidAMM set in CapitalEfficiencyEngine`);

    // ========== STEP 10: SETUP ROLES ==========
    console.log("\n📦 [13/13] Setting up roles...");
    const BORROWER_OPS_ROLE = await accessControl.BORROWER_OPS_ROLE();
    const TROVE_MANAGER_ROLE = await accessControl.TROVE_MANAGER_ROLE();

    await accessControl.grantRole(BORROWER_OPS_ROLE, addresses.borrowerOpsV2);
    await accessControl.grantRole(TROVE_MANAGER_ROLE, addresses.troveManagerV2);
    console.log("   ✅ Roles configured");

    // Setup USDF minting
    try {
      await (usdf as any).addMinter(addresses.borrowerOpsV2);
      await (usdf as any).addMinter(addresses.liquidityCore);
      console.log("   ✅ USDF minter roles granted");
    } catch (e) {
      console.log("   ⚠️  USDF minting setup skipped (may not be available)");
    }

    // ========== SUMMARY ==========
    console.log("\n" + "=".repeat(80));
    console.log("✅ DEPLOYMENT COMPLETE!");
    console.log("=".repeat(80));

    console.log("\n📋 Deployed Contracts:");
    console.log(`├─ AccessControlManager: ${addresses.accessControl}`);
    console.log(`├─ USDF Token:           ${addresses.usdf}`);
    console.log(`├─ Mock WETH:            ${addresses.weth}`);
    console.log(`├─ Mock WBTC:            ${addresses.wbtc}`);
    console.log(`├─ PriceOracle:          ${addresses.priceOracle}`);
    console.log(`├─ UnifiedLiquidityPool: ${addresses.unifiedLiquidityPool}`);
    console.log(`├─ LiquidityCore:        ${addresses.liquidityCore}`);
    console.log(`├─ SortedTroves:         ${addresses.sortedTroves}`);
    console.log(`├─ BorrowerOperationsV2: ${addresses.borrowerOpsV2}`);
    console.log(`├─ TroveManagerV2:       ${addresses.troveManagerV2}`);
    console.log(`├─ CapitalEfficiencyEngine: ${addresses.capitalEfficiencyEngine}`);
    console.log(`└─ FluidAMM:             ${addresses.fluidAMM}`);

    console.log(`\n🔗 Polygon Amoy Testnet: ${POLYGON_AMOY_EXPLORER}/address/`);

    // ========== VERIFICATION ==========
    console.log("\n" + "=".repeat(80));
    console.log("🔍 VERIFYING CONTRACTS ON POLYGONSCAN...");
    console.log("=".repeat(80));

    // Wait for network propagation
    console.log("\n⏳ Waiting 30 seconds for network propagation...");
    await new Promise((resolve) => setTimeout(resolve, 30000));

    // Verify contracts
    await verifyContract(addresses.accessControl, []);
    await verifyContract(addresses.usdf, ["USDF Stablecoin", "USDF", 0]);
    await verifyContract(addresses.weth, ["Wrapped ETH", "WETH", 18]);
    await verifyContract(addresses.wbtc, ["Wrapped BTC", "WBTC", 8]);
    await verifyContract(addresses.priceOracle, []);

    // Save deployment addresses
    if (!fs.existsSync(DEPLOYMENT_DIR)) {
      fs.mkdirSync(DEPLOYMENT_DIR);
    }

    const deploymentFile = path.join(DEPLOYMENT_DIR, `polygon-amoy-${Date.now()}.json`);
    fs.writeFileSync(deploymentFile, JSON.stringify(addresses, null, 2));
    console.log(`\n💾 Deployment addresses saved to: ${deploymentFile}`);

    // Create summary file
    const summaryFile = path.join(DEPLOYMENT_DIR, "polygon-amoy-latest.json");
    fs.writeFileSync(summaryFile, JSON.stringify(addresses, null, 2));

    console.log("\n" + "=".repeat(80));
    console.log("🎉 DEPLOYMENT SUCCESSFUL!");
    console.log("=".repeat(80));
    console.log("\n📖 Next Steps:");
    console.log("1. Get testnet MATIC: https://faucet.polygon.technology/");
    console.log("2. Check block explorer: https://amoy.polygonscan.com/");
    console.log("3. Update frontend with contract addresses above");
    console.log("4. Deploy to mainnet when ready");
    console.log("\n");

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

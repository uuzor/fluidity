import { ethers, run } from "hardhat";
import fs from "fs";

/**
 * Deploy OrganisedSecured Contracts for Testing
 *
 * Deploys only what we have in OrganisedSecured folder:
 * - BorrowerOperationsOptimized
 * - PriceOracle
 * - LiquidityCore
 * - UnifiedLiquidityPool
 * - SortedTroves
 * - Supporting contracts (AccessControl, USDF, Mock tokens)
 *
 * Purpose: Test the optimized BorrowerOperations and PriceOracle on testnet
 *
 * Usage:
 * npx hardhat run scripts/deploy-organised-secured.ts --network sonic-testnet
 */

interface DeploymentAddresses {
  // Infrastructure
  accessControlManager: string;

  // Tokens
  usdf: string;
  mockWETH: string;

  // Oracle
  priceOracle: string;
  mockChainlinkFeed: string;

  // Core OrganisedSecured contracts
  unifiedLiquidityPool: string;
  liquidityCore: string;
  sortedTroves: string;
  borrowerOperationsOptimized: string;
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
  console.log("Deploying contracts with the account:", deployer, deployer)
  const balance = await ethers.provider.getBalance(deployer.address);

  console.log("\n" + "=".repeat(70));
  console.log("🚀 DEPLOYING ORGANISEDSECURED CONTRACTS");
  console.log("=".repeat(70));
  console.log(`\n📍 Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`💼 Deployer: ${deployer.address}`);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);

  const addresses: Partial<DeploymentAddresses> = {};

  try {
    // ========== STEP 1: ACCESS CONTROL ==========
    console.log("📦 [1/8] Deploying AccessControlManager...");
    const AccessControlFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/utils/AccessControlManager.sol:AccessControlManager"
    );
    const accessControl = await AccessControlFactory.deploy();
    await accessControl.waitForDeployment();
    addresses.accessControlManager = await accessControl.getAddress();
    console.log(`   ✅ ${addresses.accessControlManager}`);

    // Grant admin role
    const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
    await accessControl.grantRole(ADMIN_ROLE, deployer.address);

    // Wait and verify
    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.accessControlManager, []);

    // ========== STEP 2: USDF TOKEN ==========
    console.log("\n📦 [2/8] Deploying USDF Token...");
    const USFDFactory = await ethers.getContractFactory("contracts/OrganisedSecured/tokens/USDF.sol:USDF");
    const usdf = await USFDFactory.deploy();
    await usdf.waitForDeployment();
    addresses.usdf = await usdf.getAddress();
    console.log(`   ✅ ${addresses.usdf}`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.usdf, []);

    // ========== STEP 3: MOCK WETH ==========
    console.log("\n📦 [3/8] Deploying Mock WETH...");
    const MockERC20Factory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockERC20.sol:MockERC20"
    );
    const weth = await MockERC20Factory.deploy(
      "Wrapped Ether",
      "WETH",
      ethers.parseEther("1000000") // 1M WETH for testing
    );
    await weth.waitForDeployment();
    addresses.mockWETH = await weth.getAddress();
    console.log(`   ✅ ${addresses.mockWETH}`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.mockWETH, [
      "Wrapped Ether",
      "WETH",
      ethers.parseEther("1000000")
    ]);

    // ========== STEP 4: PRICE ORACLE & CHAINLINK FEED ==========
    console.log("\n📦 [4/8] Deploying Mock Chainlink Feed...");
    const MockChainlinkFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockChainlinkFeed.sol:MockChainlinkFeed"
    );
    const chainlinkFeed = await MockChainlinkFactory.deploy(8); // 8 decimals
    await chainlinkFeed.waitForDeployment();
    addresses.mockChainlinkFeed = await chainlinkFeed.getAddress();
    console.log(`   ✅ ${addresses.mockChainlinkFeed}`);

    // Set ETH price to $2000
    await chainlinkFeed.setLatestRoundData(
      1, // roundId
      200000000000n, // $2000 with 8 decimals
      Math.floor(Date.now() / 1000),
      Math.floor(Date.now() / 1000),
      1
    );
    console.log(`   📊 Set ETH price: $2000`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.mockChainlinkFeed, [8]);

    console.log("\n📦 [5/8] Deploying PriceOracle...");
    const PriceOracleFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/PriceOracle.sol:PriceOracle"
    );
    const priceOracle = await PriceOracleFactory.deploy(addresses.accessControlManager!);
    await priceOracle.waitForDeployment();
    addresses.priceOracle = await priceOracle.getAddress();
    console.log(`   ✅ ${addresses.priceOracle}`);

    // Register WETH oracle
    await priceOracle.registerOracle(
      addresses.mockWETH!,
      addresses.mockChainlinkFeed!,
      3600 // 1 hour heartbeat
    );
    console.log(`   📊 Registered WETH oracle`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.priceOracle, [addresses.accessControlManager!]);

    // ========== STEP 5: UNIFIED LIQUIDITY POOL ==========
    console.log("\n📦 [6/8] Deploying UnifiedLiquidityPool...");
    const UnifiedPoolFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol:UnifiedLiquidityPool"
    );
    const unifiedPool = await UnifiedPoolFactory.deploy(addresses.accessControlManager!);
    await unifiedPool.waitForDeployment();
    addresses.unifiedLiquidityPool = await unifiedPool.getAddress();
    console.log(`   ✅ ${addresses.unifiedLiquidityPool}`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.unifiedLiquidityPool, [addresses.accessControlManager!]);

    // ========== STEP 6: LIQUIDITY CORE ==========
    console.log("\n📦 [7/8] Deploying LiquidityCore...");
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

    // Activate WETH as collateral
    await liquidityCore.activateAsset(addresses.mockWETH!);
    console.log(`   📊 Activated WETH as collateral`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.liquidityCore, [
      addresses.accessControlManager!,
      addresses.unifiedLiquidityPool!,
      addresses.usdf!
    ]);

    // ========== STEP 7: SORTED TROVES ==========
    console.log("\n📦 [8/8] Deploying SortedTroves...");
    const SortedTrovesFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/SortedTroves.sol:SortedTroves"
    );
    const sortedTroves = await SortedTrovesFactory.deploy(addresses.accessControlManager!);
    await sortedTroves.waitForDeployment();
    addresses.sortedTroves = await sortedTroves.getAddress();
    console.log(`   ✅ ${addresses.sortedTroves}`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.sortedTroves, [addresses.accessControlManager!]);

    // ========== STEP 8: BORROWER OPERATIONS OPTIMIZED ==========
    console.log("\n📦 [9/9] Deploying BorrowerOperationsOptimized...");
    const BorrowerOpsFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/BorrowerOperationsOptimized.sol:BorrowerOperationsOptimized"
    );
    const borrowerOps = await BorrowerOpsFactory.deploy(
      addresses.accessControlManager!,
      addresses.liquidityCore!,
      addresses.sortedTroves!,
      addresses.usdf!,
      addresses.priceOracle!
    );
    await borrowerOps.waitForDeployment();
    addresses.borrowerOperationsOptimized = await borrowerOps.getAddress();
    console.log(`   ✅ ${addresses.borrowerOperationsOptimized}`);

    await new Promise(r => setTimeout(r, 10000));
    await verifyContract(addresses.borrowerOperationsOptimized, [
      addresses.accessControlManager!,
      addresses.liquidityCore!,
      addresses.sortedTroves!,
      addresses.usdf!,
      addresses.priceOracle!
    ]);

    // ========== CONFIGURATION ==========
    console.log("\n" + "=".repeat(70));
    console.log("⚙️  CONFIGURING CONTRACTS");
    console.log("=".repeat(70));

    // Grant USDF permissions
    console.log("\n📝 Setting USDF permissions...");
    await usdf.addMinter(addresses.borrowerOperationsOptimized!);
    await usdf.addBurner(addresses.borrowerOperationsOptimized!);
    await usdf.addMinter(addresses.liquidityCore!);
    await usdf.addBurner(addresses.liquidityCore!);
    console.log("   ✅ USDF permissions granted");

    // Grant access control roles
    console.log("\n📝 Setting access control roles...");
    const BORROWER_OPS_ROLE = await accessControl.BORROWER_OPS_ROLE();
    await accessControl.grantRole(BORROWER_OPS_ROLE, addresses.borrowerOperationsOptimized!);
    console.log("   ✅ BORROWER_OPS_ROLE granted");

    // Note: SortedTroves doesn't need explicit configuration
    // It uses access control roles only (no setter functions)

    // Set borrowing fee (0.5%)
    console.log("\n📝 Setting borrowing fee...");
    await borrowerOps.setBorrowingFeeRate(
      addresses.mockWETH!,
      ethers.parseEther("0.005") // 0.5%
    );
    console.log("   ✅ Borrowing fee: 0.5%");

    // ========== TESTING ==========
    console.log("\n" + "=".repeat(70));
    console.log("🧪 TESTING DEPLOYMENT");
    console.log("=".repeat(70));

    // Test PriceOracle
    const ethPrice = await priceOracle.getPrice(addresses.mockWETH!);
    console.log(`\n✅ ETH Price: $${ethers.formatEther(ethPrice)}`);

    // Test BorrowerOperations constants
    const MCR = await borrowerOps.MCR();
    const MIN_NET_DEBT = await borrowerOps.MIN_NET_DEBT();
    const GAS_COMPENSATION = await borrowerOps.GAS_COMPENSATION();
    console.log(`✅ MCR: ${ethers.formatEther(MCR)} (${Number(ethers.formatEther(MCR)) * 100}%)`);
    console.log(`✅ MIN_NET_DEBT: ${ethers.formatEther(MIN_NET_DEBT)} USDF`);
    console.log(`✅ GAS_COMPENSATION: ${ethers.formatEther(GAS_COMPENSATION)} USDF`);

    // Test borrowing fee
    const feeRate = await borrowerOps.getBorrowingFeeRate(addresses.mockWETH!);
    console.log(`✅ Borrowing Fee Rate: ${Number(ethers.formatEther(feeRate)) * 100}%`);

    // Test LiquidityCore
    const isActive = await liquidityCore.isAssetActive(addresses.mockWETH!);
    console.log(`✅ WETH active in LiquidityCore: ${isActive}`);

    // ========== SUMMARY ==========
    console.log("\n" + "=".repeat(70));
    console.log("🎉 DEPLOYMENT COMPLETE!");
    console.log("=".repeat(70));

    console.log("\n📋 DEPLOYED CONTRACTS:\n");
    console.log(`AccessControlManager:          ${addresses.accessControlManager}`);
    console.log(`USDF Token:                    ${addresses.usdf}`);
    console.log(`Mock WETH:                     ${addresses.mockWETH}`);
    console.log(`Mock Chainlink Feed:           ${addresses.mockChainlinkFeed}`);
    console.log(`PriceOracle:                   ${addresses.priceOracle}`);
    console.log(`UnifiedLiquidityPool:          ${addresses.unifiedLiquidityPool}`);
    console.log(`LiquidityCore:                 ${addresses.liquidityCore}`);
    console.log(`SortedTroves:                  ${addresses.sortedTroves}`);
    console.log(`BorrowerOperationsOptimized:   ${addresses.borrowerOperationsOptimized}`);

    // Save deployment data
    const deploymentData = {
      network: {
        name: network.name,
        chainId: Number(network.chainId)
      },
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      addresses,
      configuration: {
        ethPrice: ethers.formatEther(ethPrice),
        MCR: ethers.formatEther(MCR),
        MIN_NET_DEBT: ethers.formatEther(MIN_NET_DEBT),
        GAS_COMPENSATION: ethers.formatEther(GAS_COMPENSATION),
        borrowingFeeRate: Number(ethers.formatEther(feeRate)) * 100 + "%"
      }
    };

    const filename = `organised-secured-deployment-${network.chainId}-${Date.now()}.json`;
    fs.writeFileSync(filename, JSON.stringify(deploymentData, null, 2));
    console.log(`\n💾 Deployment saved to: ${filename}`);

    console.log("\n🚀 READY TO TEST!");
    console.log("\n📝 Next steps:");
    console.log("   1. Test openTrove with BorrowerOperationsOptimized");
    console.log("   2. Verify gas usage is optimized (<200k for openTrove)");
    console.log("   3. Test PriceOracle caching with TransientStorage");
    console.log("");
    console.log("📖 Example test:");
    console.log(`   const borrowerOps = await ethers.getContractAt("BorrowerOperationsOptimized", "${addresses.borrowerOperationsOptimized}");`);
    console.log(`   const weth = await ethers.getContractAt("MockERC20", "${addresses.mockWETH}");`);
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

import { ethers } from "hardhat";
import * as fs from "fs";

/**
 * Test Local Deployment
 *
 * Simulates the full deployment on local Hardhat network to verify everything works
 * Run: npx hardhat run scripts/test-local-deployment.ts
 */

async function main() {
  console.log("\n🧪 TESTING LOCAL DEPLOYMENT (Hardhat Network)\n");
  console.log("=".repeat(70));

  const [deployer] = await ethers.getSigners();
  console.log("💼 Deployer:", deployer.address);
  console.log("💰 Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const addresses: any = {};

  try {
    // ========== STEP 1: ACCESS CONTROL ==========
    console.log("\n📦 [1/9] Deploying AccessControlManager...");
    const AccessControlFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/utils/AccessControlManager.sol:AccessControlManager"
    );
    const accessControl = await AccessControlFactory.deploy();
    await accessControl.waitForDeployment();
    addresses.accessControlManager = await accessControl.getAddress();
    console.log(`   ✅ ${addresses.accessControlManager}`);

    const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
    await accessControl.grantRole(ADMIN_ROLE, deployer.address);

    // ========== STEP 2: USDF TOKEN ==========
    console.log("\n📦 [2/9] Deploying USDF Token...");
    const USFDFactory = await ethers.getContractFactory("contracts/OrganisedSecured/tokens/USDF.sol:USDF");
    const usdf = await USFDFactory.deploy();
    await usdf.waitForDeployment();
    addresses.usdf = await usdf.getAddress();
    console.log(`   ✅ ${addresses.usdf}`);

    // ========== STEP 3: MOCK WETH ==========
    console.log("\n📦 [3/9] Deploying Mock WETH...");
    const MockERC20Factory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockERC20.sol:MockERC20"
    );
    const weth = await MockERC20Factory.deploy(
      "Wrapped Ether",
      "WETH",
      ethers.parseEther("1000000")
    );
    await weth.waitForDeployment();
    addresses.mockWETH = await weth.getAddress();
    console.log(`   ✅ ${addresses.mockWETH}`);

    // ========== STEP 4: CHAINLINK FEED ==========
    console.log("\n📦 [4/9] Deploying Mock Chainlink Feed...");
    const MockChainlinkFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/mocks/MockChainlinkFeed.sol:MockChainlinkFeed"
    );
    const chainlinkFeed = await MockChainlinkFactory.deploy(8); // 8 decimals (standard for USD pairs)
    await chainlinkFeed.waitForDeployment();
    addresses.mockChainlinkFeed = await chainlinkFeed.getAddress();
    console.log(`   ✅ ${addresses.mockChainlinkFeed}`);

    // Set ETH price to $2000
    await chainlinkFeed.setLatestRoundData(
      1,
      ethers.parseUnits("2000", 8),
      Math.floor(Date.now() / 1000),
      Math.floor(Date.now() / 1000),
      1
    );

    // ========== STEP 5: PRICE ORACLE ==========
    console.log("\n📦 [5/9] Deploying PriceOracle...");
    const PriceOracleFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/PriceOracle.sol:PriceOracle"
    );
    const priceOracle = await PriceOracleFactory.deploy(addresses.accessControlManager);
    await priceOracle.waitForDeployment();
    addresses.priceOracle = await priceOracle.getAddress();
    console.log(`   ✅ ${addresses.priceOracle}`);

    // ========== STEP 6: UNIFIED LIQUIDITY POOL ==========
    console.log("\n📦 [6/9] Deploying UnifiedLiquidityPool...");
    const UnifiedPoolFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol:UnifiedLiquidityPool"
    );
    const unifiedPool = await UnifiedPoolFactory.deploy(
      addresses.accessControlManager
    );
    await unifiedPool.waitForDeployment();
    addresses.unifiedLiquidityPool = await unifiedPool.getAddress();
    console.log(`   ✅ ${addresses.unifiedLiquidityPool}`);

    // ========== STEP 7: LIQUIDITY CORE ==========
    console.log("\n📦 [7/9] Deploying LiquidityCore...");
    const LiquidityCoreFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/LiquidityCore.sol:LiquidityCore"
    );
    const liquidityCore = await LiquidityCoreFactory.deploy(
      addresses.accessControlManager,
      addresses.unifiedLiquidityPool,
      addresses.usdf
    );
    await liquidityCore.waitForDeployment();
    addresses.liquidityCore = await liquidityCore.getAddress();
    console.log(`   ✅ ${addresses.liquidityCore}`);

    // ========== STEP 8: SORTED TROVES ==========
    console.log("\n📦 [8/9] Deploying SortedTroves...");
    const SortedTrovesFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/SortedTroves.sol:SortedTroves"
    );
    const sortedTroves = await SortedTrovesFactory.deploy(addresses.accessControlManager);
    await sortedTroves.waitForDeployment();
    addresses.sortedTroves = await sortedTroves.getAddress();
    console.log(`   ✅ ${addresses.sortedTroves}`);

    // ========== STEP 9: BORROWER OPERATIONS ==========
    console.log("\n📦 [9/9] Deploying BorrowerOperationsOptimized...");
    const BorrowerOpsFactory = await ethers.getContractFactory(
      "contracts/OrganisedSecured/core/BorrowerOperationsOptimized.sol:BorrowerOperationsOptimized"
    );
    const borrowerOps = await BorrowerOpsFactory.deploy(
      addresses.accessControlManager,
      addresses.liquidityCore,
      addresses.priceOracle,
      addresses.sortedTroves,
      addresses.usdf
    );
    await borrowerOps.waitForDeployment();
    addresses.borrowerOperationsOptimized = await borrowerOps.getAddress();
    console.log(`   ✅ ${addresses.borrowerOperationsOptimized}`);

    // ========== CONFIGURATION ==========
    console.log("\n" + "=".repeat(70));
    console.log("⚙️  CONFIGURING CONTRACTS");
    console.log("=".repeat(70));

    // Grant USDF permissions
    console.log("\n📝 Granting USDF permissions...");
    await usdf.addMinter(addresses.borrowerOperationsOptimized);
    await usdf.addBurner(addresses.borrowerOperationsOptimized);
    await usdf.addMinter(addresses.liquidityCore);
    await usdf.addBurner(addresses.liquidityCore);
    console.log("   ✅ USDF permissions granted");

    // Grant access control roles
    console.log("\n📝 Setting access control roles...");
    const BORROWER_OPS_ROLE = await accessControl.BORROWER_OPS_ROLE();
    await accessControl.grantRole(BORROWER_OPS_ROLE, addresses.borrowerOperationsOptimized);
    console.log("   ✅ BORROWER_OPS_ROLE granted");

    // Set borrowing fee (0.5%)
    console.log("\n📝 Setting borrowing fee...");
    await borrowerOps.setBorrowingFeeRate(
      addresses.mockWETH,
      ethers.parseEther("0.005")
    );
    console.log("   ✅ Borrowing fee: 0.5%");

    // Activate WETH in LiquidityCore
    console.log("\n📝 Activating WETH...");
    await liquidityCore.activateAsset(addresses.mockWETH);
    console.log("   ✅ WETH activated");

    // Register oracle
    console.log("\n📝 Registering PriceOracle...");
    await priceOracle.registerOracle(
      addresses.mockWETH,
      addresses.mockChainlinkFeed,
      3600
    );
    console.log("   ✅ Oracle registered ($2000 ETH, 1-hour heartbeat)");

    // ========== TESTING ==========
    console.log("\n" + "=".repeat(70));
    console.log("🧪 TESTING DEPLOYMENT");
    console.log("=".repeat(70));

    // MockPriceOracle doesn't have getRegisteredAssets

    const ethPrice = await priceOracle.getPrice(addresses.mockWETH);
    console.log(`\n✅ ETH Price: $${ethers.formatEther(ethPrice)}`);

    const MCR = await borrowerOps.MCR();
    const MIN_NET_DEBT = await borrowerOps.MIN_NET_DEBT();
    const GAS_COMPENSATION = await borrowerOps.GAS_COMPENSATION();
    console.log(`✅ MCR: ${ethers.formatEther(MCR)} (${Number(ethers.formatEther(MCR)) * 100}%)`);
    console.log(`✅ MIN_NET_DEBT: ${ethers.formatEther(MIN_NET_DEBT)} USDF`);
    console.log(`✅ GAS_COMPENSATION: ${ethers.formatEther(GAS_COMPENSATION)} USDF`);

    const feeRate = await borrowerOps.getBorrowingFeeRate(addresses.mockWETH);
    console.log(`✅ Borrowing Fee Rate: ${Number(ethers.formatEther(feeRate)) * 100}%`);

    const isActive = await liquidityCore.isAssetActive(addresses.mockWETH);
    console.log(`✅ WETH active in LiquidityCore: ${isActive}`);

    // ========== FUNCTIONAL TEST: OPEN TROVE ==========
    console.log("\n" + "=".repeat(70));
    console.log("🔓 FUNCTIONAL TEST: Opening Trove");
    console.log("=".repeat(70));

    // Mint WETH to deployer
    await weth.mint(deployer.address, ethers.parseEther("100"));
    const wethBalance = await weth.balanceOf(deployer.address);
    console.log(`\n💰 Minted ${ethers.formatEther(wethBalance)} WETH`);

    // Approve BorrowerOps
    await weth.approve(addresses.borrowerOperationsOptimized, ethers.parseEther("10"));
    console.log("✅ Approved 10 WETH");

    // Open trove
    console.log("\n🔓 Opening trove (10 WETH collateral, 10,000 USDF debt)...");
    const tx = await borrowerOps.openTrove(
      addresses.mockWETH,
      ethers.parseEther("0.05"), // Max 5% fee
      ethers.parseEther("10"),   // 10 WETH
      ethers.parseEther("10000"), // 10,000 USDF
      ethers.ZeroAddress,
      ethers.ZeroAddress
    );

    const receipt = await tx.wait();
    console.log(`✅ Trove opened! Gas used: ${receipt?.gasUsed}`);

    // Check trove
    const [debt, coll] = await borrowerOps.getEntireDebtAndColl(
      deployer.address,
      addresses.mockWETH
    );

    console.log(`\n📊 Trove Details:`);
    console.log(`   Debt: ${ethers.formatEther(debt)} USDF`);
    console.log(`   Collateral: ${ethers.formatEther(coll)} WETH`);
    console.log(`   Collateral Value: $${Number(ethers.formatEther(coll)) * Number(ethers.formatEther(ethPrice))}`);
    console.log(`   Collateral Ratio: ${(Number(ethers.formatEther(coll)) * Number(ethers.formatEther(ethPrice)) / Number(ethers.formatEther(debt)) * 100).toFixed(2)}%`);

    // Check USDF balance
    const usdfBalance = await usdf.balanceOf(deployer.address);
    console.log(`   USDF Balance: ${ethers.formatEther(usdfBalance)}`);

    // ========== SUMMARY ==========
    console.log("\n" + "=".repeat(70));
    console.log("🎉 LOCAL DEPLOYMENT TEST COMPLETE!");
    console.log("=".repeat(70));

    console.log("\n📋 All Systems Operational:\n");
    console.log("✅ All 9 contracts deployed");
    console.log("✅ Configuration completed");
    console.log("✅ PriceOracle working ($2000)");
    console.log("✅ BorrowerOperations working");
    console.log("✅ Trove opened successfully");
    console.log(`✅ Gas usage: ${receipt?.gasUsed} (target: <200,000)`);

    console.log("\n🚀 READY FOR TESTNET DEPLOYMENT!");
    console.log("\nRun: npx hardhat run scripts/deploy-organised-secured.ts --network sonic-testnet");

  } catch (error: any) {
    console.error("\n❌ TEST FAILED:", error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

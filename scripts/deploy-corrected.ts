import { ethers } from "hardhat";
import fs from "fs";

interface DeploymentAddresses {
  usdf: string;
  fluidToken: string;
  priceOracle: string;
  sortedTroves: string;
  liquidationHelpers: string;
  troveManager: string;
  borrowerOperations: string;
  stabilityPool: string;
  activePool: string;
  defaultPool: string;
  collSurplusPool: string;
  gasPool: string;
  accessControlManager: string;
  mockChainlinkFeed: string;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("🚀 Starting Fluid Protocol deployment...");
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const deployedAddresses: Partial<DeploymentAddresses> = {};

  try {
    // Step 1: Deploy Access Control Manager
    console.log("\n=== Deploying Access Control Manager ===");
    const AccessControlManager = await ethers.getContractFactory("AccessControlManager");
    const accessControlManager = await AccessControlManager.deploy();
    await accessControlManager.waitForDeployment();
    deployedAddresses.accessControlManager = await accessControlManager.getAddress();
    console.log("✅ AccessControlManager deployed to:", deployedAddresses.accessControlManager);

    // Step 2: Deploy Token Contracts
    console.log("\n=== Deploying Token Contracts ===");
    
    // Deploy USDF
    const USDF = await ethers.getContractFactory("USDF");
    const usdf = await USDF.deploy();
    await usdf.waitForDeployment();
    deployedAddresses.usdf = await usdf.getAddress();
    console.log("✅ USDF deployed to:", deployedAddresses.usdf);

    // Deploy Fluid Token
    const FluidToken = await ethers.getContractFactory("FluidToken");
    const fluidToken = await FluidToken.deploy();
    await fluidToken.waitForDeployment();
    deployedAddresses.fluidToken = await fluidToken.getAddress();
    console.log("✅ FluidToken deployed to:", deployedAddresses.fluidToken);

    // Step 3: Deploy Price Oracle and Mock Feed
    console.log("\n=== Deploying Price Oracle ===");
    
    // Deploy Mock Chainlink Feed for testing (ETH/USD at $2000)
    const MockChainlinkFeed = await ethers.getContractFactory("MockChainlinkFeed");
    const mockChainlinkFeed = await MockChainlinkFeed.deploy(200000000000, 8); // $2000 with 8 decimals
    await mockChainlinkFeed.waitForDeployment();
    deployedAddresses.mockChainlinkFeed = await mockChainlinkFeed.getAddress();
    console.log("✅ MockChainlinkFeed deployed to:", deployedAddresses.mockChainlinkFeed);

    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await PriceOracle.deploy();
    await priceOracle.waitForDeployment();
    deployedAddresses.priceOracle = await priceOracle.getAddress();
    console.log("✅ PriceOracle deployed to:", deployedAddresses.priceOracle);

    // Add ETH price feed to oracle
    await priceOracle.addOracle(ethers.ZeroAddress, deployedAddresses.mockChainlinkFeed, 3600);
    console.log("✅ Added ETH oracle to PriceOracle");

    // Step 4: Deploy Core Infrastructure (non-dependent contracts first)
    console.log("\n=== Deploying Core Infrastructure ===");

    // Deploy SortedTroves
    const SortedTroves = await ethers.getContractFactory("SortedTroves");
    const sortedTroves = await SortedTroves.deploy();
    await sortedTroves.waitForDeployment();
    deployedAddresses.sortedTroves = await sortedTroves.getAddress();
    console.log("✅ SortedTroves deployed to:", deployedAddresses.sortedTroves);

    // Deploy LiquidationHelpers library
    const LiquidationHelpers = await ethers.getContractFactory("LiquidationHelpers");
    const liquidationHelpers = await LiquidationHelpers.deploy();
    await liquidationHelpers.waitForDeployment();
    deployedAddresses.liquidationHelpers = await liquidationHelpers.getAddress();
    console.log("✅ LiquidationHelpers library deployed to:", deployedAddresses.liquidationHelpers);

    // Deploy Pool Contracts
    console.log("\n=== Deploying Pool Contracts ===");

    const ActivePool = await ethers.getContractFactory("ActivePool");
    const activePool = await ActivePool.deploy();
    await activePool.waitForDeployment();
    deployedAddresses.activePool = await activePool.getAddress();
    console.log("✅ ActivePool deployed to:", deployedAddresses.activePool);

    const DefaultPool = await ethers.getContractFactory("DefaultPool");
    const defaultPool = await DefaultPool.deploy();
    await defaultPool.waitForDeployment();
    deployedAddresses.defaultPool = await defaultPool.getAddress();
    console.log("✅ DefaultPool deployed to:", deployedAddresses.defaultPool);

    const CollSurplusPool = await ethers.getContractFactory("CollSurplusPool");
    const collSurplusPool = await CollSurplusPool.deploy();
    await collSurplusPool.waitForDeployment();
    deployedAddresses.collSurplusPool = await collSurplusPool.getAddress();
    console.log("✅ CollSurplusPool deployed to:", deployedAddresses.collSurplusPool);

    const GasPool = await ethers.getContractFactory("GasPool");
    const gasPool = await GasPool.deploy();
    await gasPool.waitForDeployment();
    deployedAddresses.gasPool = await gasPool.getAddress();
    console.log("✅ GasPool deployed to:", deployedAddresses.gasPool);

    // Step 5: Deploy Core Protocols with proper dependency order
    console.log("\n=== Deploying Core Protocol Contracts ===");

    // First, deploy SecureTroveManager with placeholder for stability pool
    const SecureTroveManager = await ethers.getContractFactory("SecureTroveManager", {
      libraries: {
        LiquidationHelpers: deployedAddresses.liquidationHelpers,
      },
    });
    const troveManager = await SecureTroveManager.deploy(
      deployedAddresses.accessControlManager,
      deployedAddresses.usdf,
      ethers.ZeroAddress, // stabilityPool - placeholder
      deployedAddresses.priceOracle,
      deployedAddresses.sortedTroves,
      ethers.ZeroAddress, // borrowerOperations - placeholder
      deployedAddresses.activePool,
      deployedAddresses.defaultPool,
      deployedAddresses.collSurplusPool,
      deployedAddresses.gasPool
    );
    await troveManager.waitForDeployment();
    deployedAddresses.troveManager = await troveManager.getAddress();
    console.log("✅ SecureTroveManager deployed to:", deployedAddresses.troveManager);

    // Deploy SecureBorrowerOperations with TroveManager address
    const SecureBorrowerOperations = await ethers.getContractFactory("SecureBorrowerOperations");
    const borrowerOperations = await SecureBorrowerOperations.deploy(
      deployedAddresses.accessControlManager,
      deployedAddresses.troveManager,
      deployedAddresses.usdf,
      deployedAddresses.priceOracle,
      deployedAddresses.activePool,
      deployedAddresses.defaultPool,
      ethers.ZeroAddress, // stabilityPool - placeholder
      deployedAddresses.gasPool,
      deployedAddresses.collSurplusPool,
      deployedAddresses.sortedTroves
    );
    await borrowerOperations.waitForDeployment();
    deployedAddresses.borrowerOperations = await borrowerOperations.getAddress();
    console.log("✅ SecureBorrowerOperations deployed to:", deployedAddresses.borrowerOperations);

    // Now deploy SecureStabilityPool with all required addresses
    const SecureStabilityPool = await ethers.getContractFactory("SecureStabilityPool");
    const stabilityPool = await SecureStabilityPool.deploy(
      deployedAddresses.accessControlManager,
      deployedAddresses.usdf,
      deployedAddresses.fluidToken,
      deployedAddresses.troveManager,
      deployedAddresses.borrowerOperations,
      deployedAddresses.activePool,
      ethers.ZeroAddress // communityIssuance - placeholder for now
    );
    await stabilityPool.waitForDeployment();
    deployedAddresses.stabilityPool = await stabilityPool.getAddress();
    console.log("✅ SecureStabilityPool deployed to:", deployedAddresses.stabilityPool);

    // Step 6: Initialize Pool Contracts (these use the old initialize pattern)
    console.log("\n=== Initializing Pool Contracts ===");

    // Initialize pool contracts
    await activePool.setAddresses(
      deployedAddresses.borrowerOperations,
      deployedAddresses.troveManager,
      deployedAddresses.stabilityPool,
      deployedAddresses.defaultPool
    );
    console.log("✅ ActivePool initialized");

    await defaultPool.setAddresses(
      deployedAddresses.troveManager,
      deployedAddresses.activePool
    );
    console.log("✅ DefaultPool initialized");

    await collSurplusPool.setAddresses(
      deployedAddresses.borrowerOperations,
      deployedAddresses.troveManager,
      deployedAddresses.activePool
    );
    console.log("✅ CollSurplusPool initialized");

    await gasPool.setUSDF(deployedAddresses.usdf);
    console.log("✅ GasPool initialized");

    // Set authorized contracts for SortedTroves
    await sortedTroves.setTroveManager(deployedAddresses.troveManager);
    await sortedTroves.setBorrowerOperations(deployedAddresses.borrowerOperations);
    await sortedTroves.setMaxSize(ethers.ZeroAddress, 10000); // Max 10k troves for ETH
    console.log("✅ SortedTroves initialized");

    // Step 7: Set up Permissions
    console.log("\n=== Setting up Permissions ===");

    // Grant minter and burner roles to protocol contracts
    await usdf.addMinter(deployedAddresses.borrowerOperations);
    await usdf.addBurner(deployedAddresses.borrowerOperations);
    await usdf.addMinter(deployedAddresses.troveManager);
    await usdf.addBurner(deployedAddresses.troveManager);
    await usdf.addMinter(deployedAddresses.stabilityPool);
    await usdf.addBurner(deployedAddresses.stabilityPool);
    console.log("✅ USDF permissions set");

    // Set up access control roles
    const LIQUIDATOR_ROLE = await accessControlManager.LIQUIDATOR_ROLE();
    const ADMIN_ROLE = await accessControlManager.ADMIN_ROLE();
    
    await accessControlManager.grantRole(ADMIN_ROLE, deployer.address);
    await accessControlManager.grantRole(LIQUIDATOR_ROLE, deployer.address);
    console.log("✅ Access control roles set");

    // Step 8: Verify Deployment
    console.log("\n=== Verifying Deployment ===");
    
    // Test price oracle
    const ethPrice = await priceOracle.getPrice(ethers.ZeroAddress);
    console.log("✅ ETH Price from oracle:", ethers.formatEther(ethPrice), "USD");

    // Test USDF
    const usdfName = await usdf.name();
    const usdfSymbol = await usdf.symbol();
    console.log(`✅ USDF Token: ${usdfName} (${usdfSymbol})`);

    // Test FluidToken
    const fluidName = await fluidToken.name();
    const fluidSymbol = await fluidToken.symbol();
    const fluidSupply = await fluidToken.totalSupply();
    console.log(`✅ Fluid Token: ${fluidName} (${fluidSymbol}), Total Supply: ${ethers.formatEther(fluidSupply)}`);

    // Final deployment summary
    console.log("\n🎉 === DEPLOYMENT SUMMARY ===");
    console.log("All contracts deployed and initialized successfully!");
    console.log("\n📋 Contract Addresses:");
    
    Object.entries(deployedAddresses).forEach(([name, address]) => {
      console.log(`${name}: ${address}`);
    });

    // Save deployment addresses to file
    const deploymentData = {
      network: await ethers.provider.getNetwork(),
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      addresses: deployedAddresses
    };
    
    const filename = `deployments-corrected-${deploymentData.network.chainId}.json`;
    fs.writeFileSync(filename, JSON.stringify(deploymentData, null, 2));
    console.log(`\n💾 Deployment addresses saved to ${filename}`);

    console.log("\n⚠️  === IMPORTANT NOTES ===");
    console.log("⚠️  Some constructor parameters use placeholder addresses (ZeroAddress)");
    console.log("⚠️  This is due to circular dependencies in the secure contracts");
    console.log("⚠️  Consider implementing a proxy pattern or factory pattern for production");
    console.log("⚠️  Thoroughly test all contract interactions before mainnet deployment");

    console.log("\n📝 === NEXT STEPS ===");
    console.log("1. Verify contracts on block explorer");
    console.log("2. Test all contract interactions thoroughly");
    console.log("3. Set up governance parameters");
    console.log("4. Add additional price oracles for other assets");
    console.log("5. Configure liquidation parameters");
    console.log("6. Set up monitoring and alerts");
    console.log("7. Consider upgrading to proxy pattern for production");

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    
    // Print partial deployment for debugging
    if (Object.keys(deployedAddresses).length > 0) {
      console.log("\nPartially deployed contracts:");
      Object.entries(deployedAddresses).forEach(([name, address]) => {
        console.log(`${name}: ${address}`);
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
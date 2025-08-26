import { ethers, upgrades } from "hardhat";
import fs from "fs";

interface ProxyDeploymentAddresses {
  // Token contracts
  usdf: string;
  fluidToken: string;
  
  // Oracle and infrastructure
  priceOracle: string;
  mockChainlinkFeed: string;
  sortedTroves: string;
  liquidationHelpers: string;
  
  // Pool contracts
  activePool: string;
  defaultPool: string;
  collSurplusPool: string;
  gasPool: string;
  
  // Access control
  accessControlManager: string;
  
  // Proxy contracts
  troveManagerProxy: string;
  troveManagerImplementation: string;
  borrowerOperationsProxy: string;
  borrowerOperationsImplementation: string;
  stabilityPoolProxy: string;
  stabilityPoolImplementation: string;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("🚀 Starting Fluid Protocol Proxy Deployment...");
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const deployedAddresses: Partial<ProxyDeploymentAddresses> = {};

  try {
    // Step 1: Deploy Access Control Manager
    console.log("\n=== Step 1: Deploying Access Control Manager ===");
    const AccessControlManager = await ethers.getContractFactory("AccessControlManager");
    const accessControlManager = await AccessControlManager.deploy();
    await accessControlManager.waitForDeployment();
    deployedAddresses.accessControlManager = await accessControlManager.getAddress();
    console.log("✅ AccessControlManager deployed to:", deployedAddresses.accessControlManager);

    // Step 2: Deploy Token Contracts
    console.log("\n=== Step 2: Deploying Token Contracts ===");
    
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

    // Step 3: Deploy Oracle Infrastructure
    console.log("\n=== Step 3: Deploying Oracle Infrastructure ===");
    
    // Deploy Mock Chainlink Feed
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

    // Configure price oracle
    await priceOracle.addOracle(ethers.ZeroAddress, deployedAddresses.mockChainlinkFeed, 3600);
    console.log("✅ Added ETH oracle to PriceOracle");

    // Step 4: Deploy Supporting Infrastructure
    console.log("\n=== Step 4: Deploying Supporting Infrastructure ===");

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

    // Step 5: Deploy Upgradeable Core Contracts using Proxy Pattern
    console.log("\n=== Step 5: Deploying Upgradeable Core Contracts ===");

    // Deploy TroveManager Proxy
    console.log("\n--- Deploying TroveManager Proxy ---");
    const TroveManagerFactory = await ethers.getContractFactory("UpgradeableTroveManager", {
      libraries: {
        LiquidationHelpers: deployedAddresses.liquidationHelpers,
      },
    });
    
    const troveManagerProxy = await upgrades.deployProxy(
      TroveManagerFactory,
      [
        deployedAddresses.accessControlManager,
        deployedAddresses.usdf,
        deployedAddresses.priceOracle,
        deployedAddresses.sortedTroves
      ],
      { 
        initializer: 'initialize',
        kind: 'uups',
        unsafeAllowLinkedLibraries: true
      }
    );
    await troveManagerProxy.waitForDeployment();
    
    deployedAddresses.troveManagerProxy = await troveManagerProxy.getAddress();
    deployedAddresses.troveManagerImplementation = await upgrades.erc1967.getImplementationAddress(
      deployedAddresses.troveManagerProxy
    );
    console.log("✅ TroveManager Proxy deployed to:", deployedAddresses.troveManagerProxy);
    console.log("✅ TroveManager Implementation at:", deployedAddresses.troveManagerImplementation);

    // Deploy BorrowerOperations Proxy
    console.log("\n--- Deploying BorrowerOperations Proxy ---");
    const BorrowerOperationsFactory = await ethers.getContractFactory("UpgradeableBorrowerOperations");
    
    const borrowerOperationsProxy = await upgrades.deployProxy(
      BorrowerOperationsFactory,
      [
        deployedAddresses.accessControlManager,
        deployedAddresses.usdf,
        deployedAddresses.priceOracle,
        deployedAddresses.sortedTroves
      ],
      { 
        initializer: 'initialize',
        kind: 'uups'
      }
    );
    await borrowerOperationsProxy.waitForDeployment();
    
    deployedAddresses.borrowerOperationsProxy = await borrowerOperationsProxy.getAddress();
    deployedAddresses.borrowerOperationsImplementation = await upgrades.erc1967.getImplementationAddress(
      deployedAddresses.borrowerOperationsProxy
    );
    console.log("✅ BorrowerOperations Proxy deployed to:", deployedAddresses.borrowerOperationsProxy);
    console.log("✅ BorrowerOperations Implementation at:", deployedAddresses.borrowerOperationsImplementation);

    // Deploy StabilityPool Proxy
    console.log("\n--- Deploying StabilityPool Proxy ---");
    const StabilityPoolFactory = await ethers.getContractFactory("UpgradeableStabilityPool");
    
    const stabilityPoolProxy = await upgrades.deployProxy(
      StabilityPoolFactory,
      [
        deployedAddresses.accessControlManager,
        deployedAddresses.usdf,
        deployedAddresses.fluidToken
      ],
      { 
        initializer: 'initialize',
        kind: 'uups'
      }
    );
    await stabilityPoolProxy.waitForDeployment();
    
    deployedAddresses.stabilityPoolProxy = await stabilityPoolProxy.getAddress();
    deployedAddresses.stabilityPoolImplementation = await upgrades.erc1967.getImplementationAddress(
      deployedAddresses.stabilityPoolProxy
    );
    console.log("✅ StabilityPool Proxy deployed to:", deployedAddresses.stabilityPoolProxy);
    console.log("✅ StabilityPool Implementation at:", deployedAddresses.stabilityPoolImplementation);

    // Step 6: Configure Cross-Contract References (Solving Circular Dependencies)
    console.log("\n=== Step 6: Configuring Cross-Contract References ===");

    // Set contract addresses in TroveManager
    await troveManagerProxy.setContractAddresses(
      deployedAddresses.stabilityPoolProxy,
      deployedAddresses.borrowerOperationsProxy,
      deployedAddresses.activePool,
      deployedAddresses.defaultPool,
      deployedAddresses.collSurplusPool,
      deployedAddresses.gasPool
    );
    console.log("✅ TroveManager contract addresses configured");

    // Set contract addresses in BorrowerOperations
    await borrowerOperationsProxy.setContractAddresses(
      deployedAddresses.troveManagerProxy,
      deployedAddresses.stabilityPoolProxy,
      deployedAddresses.activePool,
      deployedAddresses.defaultPool,
      deployedAddresses.collSurplusPool,
      deployedAddresses.gasPool
    );
    console.log("✅ BorrowerOperations contract addresses configured");

    // Set contract addresses in StabilityPool
    await stabilityPoolProxy.setContractAddresses(
      deployedAddresses.troveManagerProxy,
      deployedAddresses.borrowerOperationsProxy,
      deployedAddresses.activePool,
      ethers.ZeroAddress // communityIssuance - placeholder
    );
    console.log("✅ StabilityPool contract addresses configured");

    // Step 7: Initialize Pool Contracts
    console.log("\n=== Step 7: Initializing Pool Contracts ===");

    // Initialize pool contracts
    await activePool.setAddresses(
      deployedAddresses.borrowerOperationsProxy,
      deployedAddresses.troveManagerProxy,
      deployedAddresses.stabilityPoolProxy,
      deployedAddresses.defaultPool
    );
    console.log("✅ ActivePool initialized");

    await defaultPool.setAddresses(
      deployedAddresses.troveManagerProxy,
      deployedAddresses.activePool
    );
    console.log("✅ DefaultPool initialized");

    await collSurplusPool.setAddresses(
      deployedAddresses.borrowerOperationsProxy,
      deployedAddresses.troveManagerProxy,
      deployedAddresses.activePool
    );
    console.log("✅ CollSurplusPool initialized");

    await gasPool.setUSDF(deployedAddresses.usdf);
    console.log("✅ GasPool initialized");

    // Configure SortedTroves
    await sortedTroves.setTroveManager(deployedAddresses.troveManagerProxy);
    await sortedTroves.setBorrowerOperations(deployedAddresses.borrowerOperationsProxy);
    await sortedTroves.setMaxSize(ethers.ZeroAddress, 10000); // Max 10k troves for ETH
    console.log("✅ SortedTroves configured");

    // Step 8: Set up Permissions
    console.log("\n=== Step 8: Setting up Permissions ===");

    // Grant roles to proxy contracts instead of implementation contracts
    await usdf.addMinter(deployedAddresses.borrowerOperationsProxy);
    await usdf.addBurner(deployedAddresses.borrowerOperationsProxy);
    await usdf.addMinter(deployedAddresses.troveManagerProxy);
    await usdf.addBurner(deployedAddresses.troveManagerProxy);
    await usdf.addMinter(deployedAddresses.stabilityPoolProxy);
    await usdf.addBurner(deployedAddresses.stabilityPoolProxy);
    console.log("✅ USDF permissions set for proxy contracts");

    // Set up access control roles
    const LIQUIDATOR_ROLE = await accessControlManager.LIQUIDATOR_ROLE();
    const ADMIN_ROLE = await accessControlManager.ADMIN_ROLE();
    
    await accessControlManager.grantRole(ADMIN_ROLE, deployer.address);
    await accessControlManager.grantRole(LIQUIDATOR_ROLE, deployer.address);
    
    // Grant roles to proxy contracts
    await accessControlManager.grantRole(LIQUIDATOR_ROLE, deployedAddresses.troveManagerProxy);
    await accessControlManager.grantRole(LIQUIDATOR_ROLE, deployedAddresses.stabilityPoolProxy);
    console.log("✅ Access control roles configured");

    // Step 9: Verification
    console.log("\n=== Step 9: Verifying Deployment ===");
    
    // Test price oracle
    const ethPrice = await priceOracle.getPrice(ethers.ZeroAddress);
    console.log("✅ ETH Price from oracle:", ethers.formatEther(ethPrice), "USD");

    // Test tokens
    const usdfName = await usdf.name();
    const usdfSymbol = await usdf.symbol();
    console.log(`✅ USDF Token: ${usdfName} (${usdfSymbol})`);

    const fluidName = await fluidToken.name();
    const fluidSymbol = await fluidToken.symbol();
    const fluidSupply = await fluidToken.totalSupply();
    console.log(`✅ Fluid Token: ${fluidName} (${fluidSymbol}), Total Supply: ${ethers.formatEther(fluidSupply)}`);

    // Test proxy contracts
    const troveManagerTotalDebt = await troveManagerProxy.totalDebt(ethers.ZeroAddress);
    console.log("✅ TroveManager proxy working, total debt:", ethers.formatEther(troveManagerTotalDebt));

    const stabilityPoolTotalUSDF = await stabilityPoolProxy.getTotalUSDF();
    console.log("✅ StabilityPool proxy working, total USDF:", ethers.formatEther(stabilityPoolTotalUSDF));

    // Final Summary
    console.log("\n🎉 === PROXY DEPLOYMENT SUMMARY ===");
    console.log("All contracts deployed successfully using proxy pattern!");
    console.log("Circular dependencies resolved through post-deployment configuration.");
    console.log("\n📋 Contract Addresses:");
    
    Object.entries(deployedAddresses).forEach(([name, address]) => {
      console.log(`${name}: ${address}`);
    });

    // Save deployment data
    const deploymentData = {
      network: await ethers.provider.getNetwork(),
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      deploymentType: "proxy-pattern",
      addresses: deployedAddresses,
      proxyInfo: {
        note: "Core contracts deployed using UUPS proxy pattern",
        upgradeability: "Contracts can be upgraded by ADMIN_ROLE",
        circularDependencies: "Resolved using post-deployment setContractAddresses calls"
      }
    };
    
    const filename = `deployments-proxy-${deploymentData.network.chainId}.json`;
    fs.writeFileSync(filename, JSON.stringify(deploymentData, null, 2));
    console.log(`\n💾 Deployment data saved to ${filename}`);

    console.log("\n✅ === ADVANTAGES OF PROXY PATTERN ===");
    console.log("✅ Circular dependencies resolved cleanly");
    console.log("✅ Contracts are upgradeable for bug fixes and improvements");
    console.log("✅ State is preserved during upgrades");
    console.log("✅ Gas-efficient deployment and initialization");
    console.log("✅ Enhanced security through role-based access control");

    console.log("\n📝 === NEXT STEPS ===");
    console.log("1. Verify proxy contracts on block explorer");
    console.log("2. Test all contract interactions thoroughly");
    console.log("3. Set up comprehensive monitoring for proxy contracts");
    console.log("4. Implement upgrade procedures and governance");
    console.log("5. Configure additional assets and oracles");
    console.log("6. Set up automated testing for upgrade compatibility");
    console.log("7. Deploy to testnet before mainnet");

  } catch (error) {
    console.error("\n❌ Proxy deployment failed:", error);
    
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
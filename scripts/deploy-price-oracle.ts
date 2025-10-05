import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

/**
 * Deploy PriceOracle to testnet/mainnet
 *
 * Usage:
 * npx hardhat run scripts/deploy-price-oracle.ts --network sonic-testnet
 * npx hardhat run scripts/deploy-price-oracle.ts --network sonic-mainnet
 */

// Chainlink Price Feed Addresses
// UPDATE THESE WITH ACTUAL CHAINLINK FEED ADDRESSES FOR YOUR NETWORK
const CHAINLINK_FEEDS = {
  // Sonic Testnet (EXAMPLE - verify actual addresses)
  "sonic-testnet": {
    "S/USD": "0x0000000000000000000000000000000000000000", // Replace with actual feed
    "ETH/USD": "0x0000000000000000000000000000000000000000", // Replace with actual feed
    "BTC/USD": "0x0000000000000000000000000000000000000000", // Replace with actual feed
  },

  // Sonic Mainnet (EXAMPLE - verify actual addresses)
  "sonic-mainnet": {
    "S/USD": "0x0000000000000000000000000000000000000000", // Replace with actual feed
    "ETH/USD": "0x0000000000000000000000000000000000000000", // Replace with actual feed
    "BTC/USD": "0x0000000000000000000000000000000000000000", // Replace with actual feed
  },

  // Add other networks as needed
};

// Heartbeat values (seconds between price updates)
const HEARTBEATS = {
  "S/USD": 3600,    // 1 hour
  "ETH/USD": 3600,  // 1 hour
  "BTC/USD": 3600,  // 1 hour
  "USDC/USD": 86400, // 24 hours (stablecoins update less frequently)
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = (await ethers.provider.getNetwork()).name;

  console.log("\n" + "=".repeat(60));
  console.log("🚀 DEPLOYING PRICE ORACLE");
  console.log("=".repeat(60));
  console.log(`\n📍 Network: ${network}`);
  console.log(`💼 Deployer: ${deployer.address}`);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);

  // Step 1: Deploy AccessControlManager (if not already deployed)
  console.log("📦 Step 1: Deploying AccessControlManager...");
  const AccessControlFactory = await ethers.getContractFactory("AccessControlManager");
  const accessControl = await AccessControlFactory.deploy();
  await accessControl.waitForDeployment();
  const accessControlAddress = await accessControl.getAddress();
  console.log(`✅ AccessControlManager deployed to: ${accessControlAddress}\n`);

  // Grant admin role to deployer
  const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
  await accessControl.grantRole(ADMIN_ROLE, deployer.address);
  console.log(`✅ Granted ADMIN_ROLE to deployer\n`);

  // Step 2: Deploy PriceOracle
  console.log("📦 Step 2: Deploying PriceOracle...");
  const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracleFactory.deploy(accessControlAddress);
  await priceOracle.waitForDeployment();
  const priceOracleAddress = await priceOracle.getAddress();
  console.log(`✅ PriceOracle deployed to: ${priceOracleAddress}\n`);

  // Step 3: Register oracles (if Chainlink feeds are available)
  console.log("📦 Step 3: Registering Chainlink oracles...");

  const feeds = CHAINLINK_FEEDS[network as keyof typeof CHAINLINK_FEEDS];

  if (feeds) {
    for (const [pair, feedAddress] of Object.entries(feeds)) {
      if (feedAddress !== "0x0000000000000000000000000000000000000000") {
        try {
          const heartbeat = HEARTBEATS[pair as keyof typeof HEARTBEATS] || 3600;

          console.log(`  📊 Registering ${pair}...`);
          console.log(`     Feed: ${feedAddress}`);
          console.log(`     Heartbeat: ${heartbeat}s`);

          // For testnet, use feed address as asset address (simplified)
          // In production, use actual token addresses
          const tx = await priceOracle.registerOracle(
            feedAddress, // asset address (use actual token address in production)
            feedAddress, // chainlink feed address
            heartbeat
          );
          await tx.wait();

          console.log(`  ✅ Registered ${pair}\n`);
        } catch (error) {
          console.log(`  ⚠️  Failed to register ${pair}: ${error}\n`);
        }
      } else {
        console.log(`  ⚠️  Skipping ${pair} (no feed address configured)\n`);
      }
    }
  } else {
    console.log(`⚠️  No Chainlink feeds configured for network: ${network}`);
    console.log(`   Add feed addresses to CHAINLINK_FEEDS in this script\n`);
  }

  // Step 4: Save deployment info
  console.log("📦 Step 4: Saving deployment info...");

  const deployment = {
    network,
    timestamp: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      AccessControlManager: accessControlAddress,
      PriceOracle: priceOracleAddress,
    },
    chainlinkFeeds: feeds || {},
  };

  const deploymentPath = path.join(
    __dirname,
    "..",
    `deployments-price-oracle-${network}-${Date.now()}.json`
  );

  fs.writeFileSync(deploymentPath, JSON.stringify(deployment, null, 2));
  console.log(`✅ Deployment info saved to: ${deploymentPath}\n`);

  // Step 5: Verification instructions
  console.log("=".repeat(60));
  console.log("📋 NEXT STEPS:");
  console.log("=".repeat(60));
  console.log("\n1️⃣  Verify contracts on block explorer:");
  console.log(`   npx hardhat verify --network ${network} ${accessControlAddress}`);
  console.log(`   npx hardhat verify --network ${network} ${priceOracleAddress} ${accessControlAddress}`);

  console.log("\n2️⃣  Update Chainlink feed addresses:");
  console.log("   - Get actual Chainlink feed addresses for your network");
  console.log("   - Update CHAINLINK_FEEDS in this script");
  console.log("   - Re-run to register oracles");

  console.log("\n3️⃣  Test oracle functionality:");
  console.log("   - Call getPrice() for each registered asset");
  console.log("   - Verify prices are reasonable");
  console.log("   - Check price staleness");

  console.log("\n4️⃣  Integrate with BorrowerOperations:");
  console.log("   - Deploy BorrowerOperations with PriceOracle address");
  console.log("   - Update UnifiedLiquidityPool to use PriceOracle");

  console.log("\n=".repeat(60));
  console.log("✅ DEPLOYMENT COMPLETE!");
  console.log("=".repeat(60) + "\n");

  // Return deployment info for testing
  return {
    accessControl,
    priceOracle,
    deployment,
  };
}

// Execute deployment
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

export default main;

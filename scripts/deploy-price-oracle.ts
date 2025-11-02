import { ethers, run } from "hardhat";
import fs from "fs";

interface OracleDeploymentAddresses {
  accessControlManager: string;
  priceOracle: string;
  orochiAggregator: string;
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
  console.log("🚀 DEPLOYING PRICE ORACLE WITH OROCHI INTEGRATION");
  console.log("=".repeat(70));
  console.log(`\n📍 Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`💼 Deployer: ${deployer.address}`);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);

  const addresses: Partial<OracleDeploymentAddresses> = {};

  try {
    // Deploy AccessControlManager
    console.log("📦 [1/3] Deploying AccessControlManager...");
    const AccessControlFactory = await ethers.getContractFactory("AccessControlManager");
    const accessControl = await AccessControlFactory.deploy();
    await accessControl.waitForDeployment();
    addresses.accessControlManager = await accessControl.getAddress();
    console.log(`   ✅ ${addresses.accessControlManager}`);

    addresses.orochiAggregator = "0x70523434ee6a9870410960E2615406f8F9850676";
    console.log(`   📍 Using Orochi Aggregator: ${addresses.orochiAggregator}`);

    // Deploy PriceOracle
    console.log("\n📦 [2/3] Deploying PriceOracle...");
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await PriceOracleFactory.deploy(
      addresses.accessControlManager,
      addresses.orochiAggregator
    );
    await priceOracle.waitForDeployment();
    addresses.priceOracle = await priceOracle.getAddress();
    console.log(`   ✅ ${addresses.priceOracle}`);

    // Test oracle setup
    console.log("\n📦 [3/3] Testing oracle setup...");

    // Register BTC with Chainlink + Orochi symbol
    const mockBTCFeed = "0x70523434ee6a9870410960E2615406f8F9850676"; // Replace with actual Chainlink BTC feed
    await priceOracle.registerOracleWithSymbol(
      "0x70523434ee6a9870410960E2615406f8F9850676", // Replace with BTC token address
      mockBTCFeed,
      3600, // 1 hour heartbeat
      ethers.zeroPadValue(ethers.toUtf8Bytes("BTC"), 20) // _getPrice(bytes20 identifier) // _getPrice(bytes20 identifier) 
    );
    console.log("   ✅ Registered BTC oracle");

    // Get price test
    const btcPrice = await priceOracle.getPrice("0x70523434ee6a9870410960E2615406f8F9850676"); // Replace with BTC token address
    console.log(`   📊 BTC Price: $${ethers.formatEther(btcPrice)}`);

    // Get price with status test
    const priceResponse = await priceOracle.getPriceWithStatus("0x70523434ee6a9870410960E2615406f8F9850676"); 
    console.log("   📊 Price Response:");
    console.log(`      Price: $${ethers.formatEther(priceResponse.price)}`);
    console.log(`      Is Valid: ${priceResponse.isValid}`);
    console.log(`      Is Cached: ${priceResponse.isCached}`);
    console.log(`      Timestamp: ${new Date(Number(priceResponse.timestamp) * 1000)}`);

    // Save deployment data
    const deploymentData = {
      network: {
        name: network.name,
        chainId: Number(network.chainId)
      },
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      addresses,
    };

    const filename = `price-oracle-deployment-${network.chainId}-${Date.now()}.json`;
    fs.writeFileSync(filename, JSON.stringify(deploymentData, null, 2));
    console.log(`\n💾 Deployment saved to: ${filename}`);

    console.log("\n🚀 PRICE ORACLE DEPLOYMENT COMPLETE!");
    console.log("\n📋 DEPLOYED CONTRACTS:");
    console.log(`AccessControlManager: ${addresses.accessControlManager}`);
    console.log(`PriceOracle:         ${addresses.priceOracle}`);
    console.log(`Orochi Aggregator:   ${addresses.orochiAggregator}`);

  } catch (error) {
    console.error("\n❌ DEPLOYMENT FAILED:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
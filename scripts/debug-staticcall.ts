import { ethers } from "hardhat";

async function main() {
  console.log("\n🐛 DEBUG: Testing staticcall behavior\n");

  const [signer] = await ethers.getSigners();

  // Deploy MockPriceOracle
  const MockPriceOracleFactory = await ethers.getContractFactory(
    "contracts/OrganisedSecured/mocks/MockPriceOracle.sol:MockPriceOracle"
  );
  const priceOracle = await MockPriceOracleFactory.deploy();
  await priceOracle.waitForDeployment();
  const oracleAddress = await priceOracle.getAddress();

  console.log(`MockPriceOracle deployed: ${oracleAddress}`);

  // Set a price
  const testAsset = "0x1111111111111111111111111111111111111111";
  await priceOracle.setPrice(testAsset, ethers.parseEther("100"));
  console.log(`Price set for ${testAsset}: 100`);

  // Test 1: Direct call
  const directPrice = await priceOracle.getPrice(testAsset);
  console.log(`✅ Direct call works: ${ethers.formatEther(directPrice)}`);

  // Test 2: Staticcall from ethers
  const calldata = priceOracle.interface.encodeFunctionData("getPrice", [testAsset]);
  const result = await signer.call({
    to: oracleAddress,
    data: calldata
  });
  const decoded = priceOracle.interface.decodeFunctionResult("getPrice", result);
  console.log(`✅ Ethers staticcall works: ${ethers.formatEther(decoded[0])}`);

  // Test 3: Deploy a test contract that uses staticcall
  const TestStaticCall = await ethers.getContractFactory("TestStaticCallOracle");
  const testContract = await TestStaticCall.deploy(oracleAddress);
  await testContract.waitForDeployment();
  console.log(`TestStaticCallOracle deployed: ${await testContract.getAddress()}`);

  try {
    const price = await testContract.testGetPrice(testAsset);
    console.log(`✅ Contract staticcall works: ${ethers.formatEther(price)}`);
  } catch (e: any) {
    console.log(`❌ Contract staticcall failed: ${e.message}`);

    // Try with try-catch in contract
    try {
      const result = await testContract.testGetPriceWithTryCatch(testAsset);
      console.log(`Result: success=${result.success}, price=${ethers.formatEther(result.price)}`);
      if (result.errorData && result.errorData !== "0x") {
        console.log(`Error data: ${result.errorData}`);
      }
    } catch (e2: any) {
      console.log(`Still failed: ${e2.message}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

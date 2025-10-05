import { ethers } from "hardhat";

async function main() {
  const MathTestFactory = await ethers.getContractFactory("GasOptimizedMathTest");
  const mathTest = await MathTestFactory.deploy();
  await mathTest.waitForDeployment();

  // Test sqrt(100e18)
  const input = ethers.parseEther("100");
  console.log("Input:", input.toString());
  console.log("Input in hex:", input.toString(16));

  const result = await mathTest.testSqrt(input);
  console.log("Result:", result.toString());
  console.log("Expected ~10e9:", (10n ** 9n).toString());

  // Calculate actual sqrt
  const actualSqrt = Math.sqrt(Number(ethers.formatEther(input))) * 1e9;
  console.log("Actual sqrt (JS):", actualSqrt.toString());
}

main().catch(console.error);

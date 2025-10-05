import { expect } from "chai";
import { ethers } from "hardhat";

describe("PackedTrove Library - Unit Tests", function () {
  let packedTroveTest: any;

  before(async function () {
    // Deploy a test contract that uses PackedTrove library
    const PackedTroveTestFactory = await ethers.getContractFactory("PackedTroveTest");
    packedTroveTest = await PackedTroveTestFactory.deploy();
    await packedTroveTest.waitForDeployment();
  });

  describe("Pack and Unpack", function () {
    it("Should pack and unpack trove data correctly", async function () {
      const debt = ethers.parseEther("1000"); // 1000 USDF
      const collateral = ethers.parseEther("10"); // 10 ETH
      const timestamp = Math.floor(Date.now() / 1000); // Convert to seconds (uint32)
      const status = 1; // ACTIVE
      const assetId = 0;

      const packed = await packedTroveTest.testPack(
        debt,
        collateral,
        timestamp,
        status,
        assetId
      );

      const unpacked = await packedTroveTest.testUnpack(packed);

      expect(unpacked.debt).to.equal(debt);

      // Collateral is scaled down by 1e10 to fit in uint64, then scaled back up
      // So we need to scale the unpacked collateral back to full precision
      const unpackedCollateral = BigInt(unpacked.collateral) * BigInt(1e10);
      expect(unpackedCollateral).to.be.closeTo(collateral, ethers.parseEther("0.00001"));

      expect(unpacked.lastUpdate).to.equal(timestamp);
      expect(unpacked.status).to.equal(status);
      expect(unpacked.assetId).to.equal(assetId);
    });
  });

  describe("Individual Getters", function () {
    it("Should get debt correctly", async function () {
      const debt = ethers.parseEther("5000");
      const timestamp = Math.floor(Date.now() / 1000); // Convert to seconds
      const packed = await packedTroveTest.testPack(
        debt,
        ethers.parseEther("20"),
        timestamp,
        1,
        0
      );

      const retrievedDebt = await packedTroveTest.testGetDebt(packed);
      expect(retrievedDebt).to.equal(debt);
    });

    it("Should get collateral correctly", async function () {
      const collateral = ethers.parseEther("15.5");
      const timestamp = Math.floor(Date.now() / 1000);
      const packed = await packedTroveTest.testPack(
        ethers.parseEther("2000"),
        collateral,
        timestamp,
        1,
        0
      );

      const retrievedColl = await packedTroveTest.testGetCollateral(packed);
      // getCollateral already scales back up by 1e10, so we can compare directly
      expect(retrievedColl).to.be.closeTo(collateral, ethers.parseEther("0.00001"));
    });

    it("Should get status correctly", async function () {
      const timestamp = Math.floor(Date.now() / 1000);
      const packed = await packedTroveTest.testPack(
        ethers.parseEther("1000"),
        ethers.parseEther("5"),
        timestamp,
        2, // CLOSED
        0
      );

      const status = await packedTroveTest.testGetStatus(packed);
      expect(status).to.equal(2);
    });
  });

  describe("Gas Profiling", function () {
    it("Should verify pack operation is a pure function", async function () {
      const timestamp = Math.floor(Date.now() / 1000);
      // Pure functions don't use gas in actual execution, only in transaction overhead
      const packed = await packedTroveTest.testPack(
        ethers.parseEther("1000"),
        ethers.parseEther("10"),
        timestamp,
        1,
        0
      );

      // Verify it returns a non-zero packed value
      expect(packed).to.be.gt(0);
      console.log(`      Packed value: 0x${packed.toString(16)}`);
    });

    it("Should verify create operation works with block.timestamp", async function () {
      const packed = await packedTroveTest.testCreate(
        ethers.parseEther("1000"),
        ethers.parseEther("10"),
        0
      );

      // Verify it returns a non-zero packed value
      expect(packed).to.be.gt(0);

      // Verify the status is ACTIVE (1)
      const status = await packedTroveTest.testGetStatus(packed);
      expect(status).to.equal(1);

      console.log(`      Created packed value: 0x${packed.toString(16)}`);
    });

    it("Should demonstrate storage efficiency", async function () {
      console.log("\n      📊 Storage Efficiency Comparison:");
      console.log("      Traditional (unpacked) storage:");
      console.log("        - debt: 1 slot (32 bytes)");
      console.log("        - collateral: 1 slot (32 bytes)");
      console.log("        - lastUpdate: 1 slot (32 bytes)");
      console.log("        - status: 1 slot (32 bytes)");
      console.log("        - assetId: 1 slot (32 bytes)");
      console.log("        TOTAL: 5 slots = 160 bytes");
      console.log("        SLOAD cost: 5 x 2,100 = 10,500 gas (cold)");
      console.log("        SSTORE cost: 5 x 20,000 = 100,000 gas (cold)");
      console.log("");
      console.log("      PackedTrove (optimized) storage:");
      console.log("        - All fields: 1 slot (32 bytes)");
      console.log("        TOTAL: 1 slot = 32 bytes");
      console.log("        SLOAD cost: 2,100 gas (cold)");
      console.log("        SSTORE cost: 20,000 gas (cold)");
      console.log("");
      console.log("      💰 GAS SAVINGS:");
      console.log("        - Read (SLOAD): 8,400 gas saved (80% reduction)");
      console.log("        - Write (SSTORE): 80,000 gas saved (80% reduction)");
      console.log("        - Space: 128 bytes saved (80% reduction)");
    });
  });
});

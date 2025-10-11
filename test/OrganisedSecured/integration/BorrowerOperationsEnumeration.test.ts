import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  BorrowerOperationsOptimized,
  LiquidityCore,
  SortedTroves,
  MockPriceOracle,
  MockERC20,
  USDF,
  AccessControlManager,
  UnifiedLiquidityPool,
} from "../../../typechain-types";

describe("BorrowerOperations - User Trove Enumeration", function () {
  let borrowerOps: BorrowerOperationsOptimized;
  let liquidityCore: LiquidityCore;
  let sortedTroves: SortedTroves;
  let oracle: MockPriceOracle;
  let usdf: USDF;
  let accessControl: AccessControlManager;
  let unifiedPool: UnifiedLiquidityPool;

  let mockWETH: MockERC20;
  let mockWBTC: MockERC20;
  let mockUSDC: MockERC20;

  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  const ETH_PRICE = ethers.parseUnits("2000", 18); // $2000
  const BTC_PRICE = ethers.parseUnits("40000", 18); // $40000
  const USDC_PRICE = ethers.parseUnits("1", 18); // $1

  const MIN_DEBT = ethers.parseEther("2000"); // 2000 USDF
  const GAS_COMP = ethers.parseEther("200"); // 200 USDF

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    mockWETH = await MockERC20Factory.deploy("Wrapped Ether", "WETH", 18);
    mockWBTC = await MockERC20Factory.deploy("Wrapped Bitcoin", "wBTC", 8);
    mockUSDC = await MockERC20Factory.deploy("USD Coin", "USDC", 6);

    // Deploy Access Control
    const AccessControlFactory = await ethers.getContractFactory("AccessControlManager");
    accessControl = await AccessControlFactory.deploy();

    // Deploy USDF (uses its own AccessControl)
    const USDF_Factory = await ethers.getContractFactory("contracts/OrganisedSecured/tokens/USDF.sol:USDF");
    usdf = await USDF_Factory.deploy();
    await usdf.waitForDeployment();

    // Deploy UnifiedLiquidityPool
    const UnifiedPoolFactory = await ethers.getContractFactory("UnifiedLiquidityPool");
    unifiedPool = await UnifiedPoolFactory.deploy(await accessControl.getAddress());
    await unifiedPool.waitForDeployment();

    // Deploy LiquidityCore
    const LiquidityCoreFactory = await ethers.getContractFactory("LiquidityCore");
    liquidityCore = await LiquidityCoreFactory.deploy(
      await accessControl.getAddress(),
      await unifiedPool.getAddress(),
      await usdf.getAddress()
    );
    await liquidityCore.waitForDeployment();

    // Deploy Price Oracle
    const OracleFactory = await ethers.getContractFactory("MockPriceOracle");
    oracle = await OracleFactory.deploy();
    await oracle.waitForDeployment();

    // Set prices
    await oracle.setPrice(await mockWETH.getAddress(), ETH_PRICE);
    await oracle.setPrice(await mockWBTC.getAddress(), BTC_PRICE);
    await oracle.setPrice(await mockUSDC.getAddress(), USDC_PRICE);

    // Deploy SortedTroves
    const SortedTrovesFactory = await ethers.getContractFactory("SortedTroves");
    sortedTroves = await SortedTrovesFactory.deploy(await accessControl.getAddress());
    await sortedTroves.waitForDeployment();

    // Deploy BorrowerOperations
    const BorrowerOpsFactory = await ethers.getContractFactory("BorrowerOperationsOptimized");
    borrowerOps = await BorrowerOpsFactory.deploy(
      await accessControl.getAddress(),
      await liquidityCore.getAddress(),
      await sortedTroves.getAddress(),
      await usdf.getAddress(),
      await oracle.getAddress()
    );
    await borrowerOps.waitForDeployment();

    // Setup roles for AccessControlManager
    const BORROWER_OPS_ROLE = await accessControl.BORROWER_OPS_ROLE();
    await accessControl.grantRole(BORROWER_OPS_ROLE, await borrowerOps.getAddress());

    // Setup USDF roles (USDF has its own AccessControl system)
    await usdf.addMinter(await borrowerOps.getAddress());
    await usdf.addBurner(await borrowerOps.getAddress());

    // Activate assets in LiquidityCore
    await liquidityCore.activateAsset(await mockWETH.getAddress());
    await liquidityCore.activateAsset(await mockWBTC.getAddress());
    await liquidityCore.activateAsset(await mockUSDC.getAddress());

    // Mint tokens to users
    await mockWETH.mint(user1.address, ethers.parseEther("1000"));
    await mockWBTC.mint(user1.address, ethers.parseEther("100"));
    await mockUSDC.mint(user1.address, ethers.parseEther("1000000"));

    await mockWETH.mint(user2.address, ethers.parseEther("1000"));
  });

  describe("getUserTroveAssets()", function () {
    it("Should return empty array for user with no troves", async function () {
      const assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(0);
    });

    it("Should return single asset after opening one trove", async function () {
      // User1 opens WETH trove
      const collAmount = ethers.parseEther("10"); // 10 WETH
      const debtAmount = ethers.parseEther("10000"); // 10,000 USDF

      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), collAmount);
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"), // 5% max fee
        collAmount,
        debtAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      const assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(1);
      expect(assets[0]).to.equal(await mockWETH.getAddress());
    });

    it("Should return multiple assets after opening multiple troves", async function () {
      // Open WETH trove
      await mockWETH.connect(user1).approve(
        await borrowerOps.getAddress(),
        ethers.parseEther("10")
      );
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("10"),
        ethers.parseEther("10000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Open wBTC trove - use 18 decimal amounts (1 wBTC in 18 decimals = $40,000)
      // totalDebt = 15000 + fee + 200 ≈ 15,275
      // ICR = 40000 / 15275 = 261% > 110% ✓
      await mockWBTC.connect(user1).approve(
        await borrowerOps.getAddress(),
        ethers.parseEther("1")
      );
      await borrowerOps.connect(user1).openTrove(
        await mockWBTC.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("1"), // 1 wBTC (18 decimals) = $40,000
        ethers.parseEther("15000"), // 15,000 USDF
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Open USDC trove - use 18 decimal amounts (5000 USDC in 18 decimals = $5,000)
      // totalDebt = 2000 + fee + 200 ≈ 2,210
      // ICR = 5000 / 2210 = 226% > 110% ✓
      await mockUSDC.connect(user1).approve(
        await borrowerOps.getAddress(),
        ethers.parseEther("5000")
      );
      await borrowerOps.connect(user1).openTrove(
        await mockUSDC.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("5000"), // 5000 USDC (18 decimals) = $5,000
        ethers.parseEther("2000"), // 2,000 USDF
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      const assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(3);
      expect(assets).to.include(await mockWETH.getAddress());
      expect(assets).to.include(await mockWBTC.getAddress());
      expect(assets).to.include(await mockUSDC.getAddress());
    });

    it("Should remove asset after closing trove", async function () {
      // Open WETH trove
      const collAmount = ethers.parseEther("10");
      const debtAmount = ethers.parseEther("10000");

      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), collAmount);
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        collAmount,
        debtAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Verify asset in list
      let assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(1);

      // Close trove - need to mint additional USDF for fees + gas compensation
      const [debt] = await borrowerOps.getEntireDebtAndColl(
        user1.address,
        await mockWETH.getAddress()
      );
      // User only received debtAmount, but total debt includes fee + gas comp
      // Mint the difference to user (simulating they acquired it somehow)
      const usdfBalance = await usdf.balanceOf(user1.address);
      if (debt > usdfBalance) {
        await usdf.mint(user1.address, debt - usdfBalance);
      }
      await usdf.connect(user1).approve(await borrowerOps.getAddress(), debt);
      await borrowerOps.connect(user1).closeTrove(await mockWETH.getAddress());

      // Verify asset removed from list
      assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(0);
    });

    it("Should handle opening and closing multiple troves correctly", async function () {
      // Open 3 troves
      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), ethers.parseEther("10"));
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("10"),
        ethers.parseEther("10000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      await mockWBTC.connect(user1).approve(await borrowerOps.getAddress(), ethers.parseEther("1"));
      await borrowerOps.connect(user1).openTrove(
        await mockWBTC.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("1"),
        ethers.parseEther("15000"), // Adjusted for safe ICR
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      await mockUSDC.connect(user1).approve(await borrowerOps.getAddress(), ethers.parseEther("5000"));
      await borrowerOps.connect(user1).openTrove(
        await mockUSDC.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("5000"),
        ethers.parseEther("2000"), // Adjusted for safe ICR
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Verify 3 assets
      let assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(3);

      // Close middle trove (wBTC)
      const [debtBTC] = await borrowerOps.getEntireDebtAndColl(
        user1.address,
        await mockWBTC.getAddress()
      );
      await usdf.connect(user1).approve(await borrowerOps.getAddress(), debtBTC);
      await borrowerOps.connect(user1).closeTrove(await mockWBTC.getAddress());

      // Verify 2 assets remain (WETH and USDC)
      assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(2);
      expect(assets).to.include(await mockWETH.getAddress());
      expect(assets).to.include(await mockUSDC.getAddress());
      expect(assets).to.not.include(await mockWBTC.getAddress());
    });

    it("Should not duplicate asset when reopening closed trove", async function () {
      const collAmount = ethers.parseEther("10");
      const debtAmount = ethers.parseEther("10000");

      // Open trove
      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), collAmount);
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        collAmount,
        debtAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Close trove
      const [debt1] = await borrowerOps.getEntireDebtAndColl(
        user1.address,
        await mockWETH.getAddress()
      );
      // Mint additional USDF if needed (for fees + gas comp)
      const balance1 = await usdf.balanceOf(user1.address);
      if (debt1 > balance1) {
        await usdf.mint(user1.address, debt1 - balance1);
      }
      await usdf.connect(user1).approve(await borrowerOps.getAddress(), debt1);
      await borrowerOps.connect(user1).closeTrove(await mockWETH.getAddress());

      // Reopen trove
      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), collAmount);
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        collAmount,
        debtAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Should have exactly 1 asset
      const assets = await borrowerOps.getUserTroveAssets(user1.address);
      expect(assets.length).to.equal(1);
      expect(assets[0]).to.equal(await mockWETH.getAddress());
    });

    it("Should maintain separate lists for different users", async function () {
      // User1 opens WETH trove
      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), ethers.parseEther("10"));
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("10"),
        ethers.parseEther("10000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // User2 opens WETH trove
      await mockWETH.connect(user2).approve(await borrowerOps.getAddress(), ethers.parseEther("5"));
      await borrowerOps.connect(user2).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("5"),
        ethers.parseEther("5000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Both should have 1 asset
      const assetsUser1 = await borrowerOps.getUserTroveAssets(user1.address);
      const assetsUser2 = await borrowerOps.getUserTroveAssets(user2.address);

      expect(assetsUser1.length).to.equal(1);
      expect(assetsUser2.length).to.equal(1);
      expect(assetsUser1[0]).to.equal(await mockWETH.getAddress());
      expect(assetsUser2[0]).to.equal(await mockWETH.getAddress());

      // User1 closes, User2 should still have asset
      const [debt1] = await borrowerOps.getEntireDebtAndColl(
        user1.address,
        await mockWETH.getAddress()
      );
      // Mint additional USDF if needed
      const balance2 = await usdf.balanceOf(user1.address);
      if (debt1 > balance2) {
        await usdf.mint(user1.address, debt1 - balance2);
      }
      await usdf.connect(user1).approve(await borrowerOps.getAddress(), debt1);
      await borrowerOps.connect(user1).closeTrove(await mockWETH.getAddress());

      const assetsUser1After = await borrowerOps.getUserTroveAssets(user1.address);
      const assetsUser2After = await borrowerOps.getUserTroveAssets(user2.address);

      expect(assetsUser1After.length).to.equal(0);
      expect(assetsUser2After.length).to.equal(1);
    });
  });

  describe("Gas Profiling - Enumeration Overhead", function () {
    it("Should measure gas overhead for first trove (cold storage)", async function () {
      const collAmount = ethers.parseEther("10");
      const debtAmount = ethers.parseEther("10000");

      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), collAmount);

      const tx = await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        collAmount,
        debtAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      const receipt = await tx.wait();
      console.log("       Gas for openTrove (1st asset, with enumeration):", receipt?.gasUsed.toString());
    });

    it("Should measure gas overhead for second trove (warm storage)", async function () {
      // Open first trove
      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), ethers.parseEther("10"));
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("10"),
        ethers.parseEther("10000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Open second trove
      await mockWBTC.connect(user1).approve(await borrowerOps.getAddress(), ethers.parseEther("1"));
      const tx = await borrowerOps.connect(user1).openTrove(
        await mockWBTC.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("1"),
        ethers.parseEther("15000"), // Adjusted for safe ICR
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      const receipt = await tx.wait();
      console.log("       Gas for openTrove (2nd asset, with enumeration):", receipt?.gasUsed.toString());
    });

    it("Should measure gas for closeTrove with enumeration removal", async function () {
      // Open trove
      await mockWETH.connect(user1).approve(await borrowerOps.getAddress(), ethers.parseEther("10"));
      await borrowerOps.connect(user1).openTrove(
        await mockWETH.getAddress(),
        ethers.parseEther("0.05"),
        ethers.parseEther("10"),
        ethers.parseEther("10000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress
      );

      // Close trove
      const [debt] = await borrowerOps.getEntireDebtAndColl(
        user1.address,
        await mockWETH.getAddress()
      );
      // Mint additional USDF if needed
      const balance3 = await usdf.balanceOf(user1.address);
      if (debt > balance3) {
        await usdf.mint(user1.address, debt - balance3);
      }
      await usdf.connect(user1).approve(await borrowerOps.getAddress(), debt);

      const tx = await borrowerOps.connect(user1).closeTrove(await mockWETH.getAddress());
      const receipt = await tx.wait();
      console.log("       Gas for closeTrove (with enumeration removal):", receipt?.gasUsed.toString());
    });
  });
});

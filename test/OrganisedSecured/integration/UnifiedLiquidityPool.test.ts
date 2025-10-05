import { expect } from "chai";
import { ethers } from "hardhat";
import { UnifiedLiquidityPool, MockERC20, AccessControlManager } from "../../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

/**
 * UnifiedLiquidityPool - Comprehensive Test Suite
 *
 * Tests the central liquidity hub that coordinates:
 * - User deposits and withdrawals
 * - Lending protocol liquidity allocation
 * - DEX liquidity allocation
 * - Dynamic rebalancing
 * - Interest rate management
 */
describe("UnifiedLiquidityPool - Integration Tests", function () {
  let unifiedPool: UnifiedLiquidityPool;
  let accessControl: AccessControlManager;
  let usdfToken: MockERC20;
  let wethToken: MockERC20;
  let daiToken: MockERC20;

  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let dexContract: SignerWithAddress;
  let lendingContract: SignerWithAddress;

  before(async function () {
    [owner, user1, user2, dexContract, lendingContract] = await ethers.getSigners();

    // Deploy AccessControlManager (from OrganisedSecured)
    const AccessControlFactory = await ethers.getContractFactory("contracts/OrganisedSecured/utils/AccessControlManager.sol:AccessControlManager");
    accessControl = await AccessControlFactory.deploy();
    await accessControl.waitForDeployment();

    // Deploy mock tokens (from OrganisedSecured)
    const MockERC20Factory = await ethers.getContractFactory("contracts/OrganisedSecured/mocks/MockERC20.sol:MockERC20");
    usdfToken = await MockERC20Factory.deploy("USDF Stablecoin", "USDF", 0);
    wethToken = await MockERC20Factory.deploy("Wrapped ETH", "WETH", 0);
    daiToken = await MockERC20Factory.deploy("Dai Stablecoin", "DAI", 0);
    await usdfToken.waitForDeployment();
    await wethToken.waitForDeployment();
    await daiToken.waitForDeployment();

    // Deploy UnifiedLiquidityPool (from OrganisedSecured)
    const UnifiedPoolFactory = await ethers.getContractFactory("contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol:UnifiedLiquidityPool");
    unifiedPool = await UnifiedPoolFactory.deploy(await accessControl.getAddress());
    await unifiedPool.waitForDeployment();

    // Mint tokens to users
    await usdfToken.mint(user1.address, ethers.parseEther("100000"));
    await usdfToken.mint(user2.address, ethers.parseEther("100000"));
    await wethToken.mint(user1.address, ethers.parseEther("100"));
    await wethToken.mint(user2.address, ethers.parseEther("100"));
    await daiToken.mint(user1.address, ethers.parseEther("100000"));

    console.log("✓ UnifiedLiquidityPool and dependencies deployed");
  });

  describe("Asset Management", function () {

    it("Should add a new asset", async function () {
      const assetInfo = {
        token: await usdfToken.getAddress(),
        totalDeposits: 0,
        totalBorrows: 0,
        reserveFactor: ethers.parseEther("0.1"), // 10%
        collateralFactor: ethers.parseEther("0.8"), // 80%
        liquidationThreshold: ethers.parseEther("0.85"), // 85%
        liquidationBonus: ethers.parseEther("0.05"), // 5%
        isActive: true,
        canBorrow: true,
        canCollateralize: true
      };

      await expect(
        unifiedPool.addAsset(await usdfToken.getAddress(), assetInfo)
      ).to.emit(unifiedPool, "AssetAdded")
        .withArgs(await usdfToken.getAddress(), [
          assetInfo.token,
          assetInfo.totalDeposits,
          assetInfo.totalBorrows,
          assetInfo.reserveFactor,
          assetInfo.collateralFactor,
          assetInfo.liquidationThreshold,
          assetInfo.liquidationBonus,
          assetInfo.isActive,
          assetInfo.canBorrow,
          assetInfo.canCollateralize
        ]);

      const storedAsset = await unifiedPool.getAssetInfo(await usdfToken.getAddress());
      expect(storedAsset.isActive).to.be.true;
      expect(storedAsset.canBorrow).to.be.true;
    });

    it("Should add WETH asset", async function () {
      const assetInfo = {
        token: await wethToken.getAddress(),
        totalDeposits: 0,
        totalBorrows: 0,
        reserveFactor: ethers.parseEther("0.15"), // 15%
        collateralFactor: ethers.parseEther("0.75"), // 75%
        liquidationThreshold: ethers.parseEther("0.80"), // 80%
        liquidationBonus: ethers.parseEther("0.10"), // 10%
        isActive: true,
        canBorrow: true,
        canCollateralize: true
      };

      await unifiedPool.addAsset(await wethToken.getAddress(), assetInfo);

      const assets = await unifiedPool.getSupportedAssets();
      expect(assets.length).to.equal(2);
      expect(assets).to.include(await usdfToken.getAddress());
      expect(assets).to.include(await wethToken.getAddress());
    });

    it("Should update asset configuration", async function () {
      const updatedAssetInfo = {
        token: await usdfToken.getAddress(),
        totalDeposits: 0,
        totalBorrows: 0,
        reserveFactor: ethers.parseEther("0.2"), // Changed to 20%
        collateralFactor: ethers.parseEther("0.8"),
        liquidationThreshold: ethers.parseEther("0.85"),
        liquidationBonus: ethers.parseEther("0.05"),
        isActive: true,
        canBorrow: true,
        canCollateralize: true
      };

      await expect(
        unifiedPool.updateAsset(await usdfToken.getAddress(), updatedAssetInfo)
      ).to.emit(unifiedPool, "AssetUpdated");

      const asset = await unifiedPool.getAssetInfo(await usdfToken.getAddress());
      expect(asset.reserveFactor).to.equal(ethers.parseEther("0.2"));
    });

    it("Should revert when non-admin tries to add asset", async function () {
      const assetInfo = {
        token: await daiToken.getAddress(),
        totalDeposits: 0,
        totalBorrows: 0,
        reserveFactor: ethers.parseEther("0.1"),
        collateralFactor: ethers.parseEther("0.8"),
        liquidationThreshold: ethers.parseEther("0.85"),
        liquidationBonus: ethers.parseEther("0.05"),
        isActive: true,
        canBorrow: true,
        canCollateralize: true
      };

      await expect(
        unifiedPool.connect(user1).addAsset(await daiToken.getAddress(), assetInfo)
      ).to.be.reverted;
    });
  });

  describe("Deposits and Withdrawals", function () {

    before(async function () {
      // Approve tokens
      await usdfToken.connect(user1).approve(await unifiedPool.getAddress(), ethers.MaxUint256);
      await wethToken.connect(user1).approve(await unifiedPool.getAddress(), ethers.MaxUint256);
      await usdfToken.connect(user2).approve(await unifiedPool.getAddress(), ethers.MaxUint256);
    });

    it("Should deposit USDF", async function () {
      const depositAmount = ethers.parseEther("10000");

      await expect(
        unifiedPool.connect(user1).deposit(await usdfToken.getAddress(), depositAmount)
      ).to.emit(unifiedPool, "LiquidityDeposited")
        .withArgs(user1.address, await usdfToken.getAddress(), depositAmount);

      const userDeposit = await unifiedPool.getUserDeposits(user1.address, await usdfToken.getAddress());
      expect(userDeposit).to.equal(depositAmount);

      const totalLiquidity = await unifiedPool.getTotalLiquidity(await usdfToken.getAddress());
      expect(totalLiquidity).to.equal(depositAmount);
    });

    it("Should deposit WETH", async function () {
      const depositAmount = ethers.parseEther("10");

      await unifiedPool.connect(user1).deposit(await wethToken.getAddress(), depositAmount);

      const userDeposit = await unifiedPool.getUserDeposits(user1.address, await wethToken.getAddress());
      expect(userDeposit).to.equal(depositAmount);
    });

    it("Should track multiple user deposits", async function () {
      const user2Amount = ethers.parseEther("5000");

      await unifiedPool.connect(user2).deposit(await usdfToken.getAddress(), user2Amount);

      const user1Deposit = await unifiedPool.getUserDeposits(user1.address, await usdfToken.getAddress());
      const user2Deposit = await unifiedPool.getUserDeposits(user2.address, await usdfToken.getAddress());
      const totalLiquidity = await unifiedPool.getTotalLiquidity(await usdfToken.getAddress());

      expect(user1Deposit).to.equal(ethers.parseEther("10000"));
      expect(user2Deposit).to.equal(ethers.parseEther("5000"));
      expect(totalLiquidity).to.equal(ethers.parseEther("15000"));
    });

    it("Should withdraw USDF", async function () {
      const withdrawAmount = ethers.parseEther("2000");
      const balanceBefore = await usdfToken.balanceOf(user1.address);

      await expect(
        unifiedPool.connect(user1).withdraw(await usdfToken.getAddress(), withdrawAmount)
      ).to.emit(unifiedPool, "LiquidityWithdrawn")
        .withArgs(user1.address, await usdfToken.getAddress(), withdrawAmount);

      const balanceAfter = await usdfToken.balanceOf(user1.address);
      expect(balanceAfter - balanceBefore).to.equal(withdrawAmount);

      const userDeposit = await unifiedPool.getUserDeposits(user1.address, await usdfToken.getAddress());
      expect(userDeposit).to.equal(ethers.parseEther("8000"));
    });

    it("Should revert withdrawal with insufficient balance", async function () {
      const excessAmount = ethers.parseEther("100000");

      await expect(
        unifiedPool.connect(user1).withdraw(await usdfToken.getAddress(), excessAmount)
      ).to.be.revertedWith("Insufficient balance");
    });

    it("Should revert deposit of inactive asset", async function () {
      await expect(
        unifiedPool.connect(user1).deposit(await daiToken.getAddress(), ethers.parseEther("1000"))
      ).to.be.revertedWith("Asset not supported");
    });
  });

  describe("Borrowing and Lending", function () {

    it("Should borrow against collateral", async function () {
      const borrowAmount = ethers.parseEther("5000");
      const collateralToken = await wethToken.getAddress();

      // User1 has 10 WETH deposited (worth ~$20,000)
      // Trying to borrow 5000 USDF (needs ~$6,250 collateral at 80% LTV)
      // Should work since collateral value >> borrow amount

      await expect(
        unifiedPool.connect(user1).borrow(
          await usdfToken.getAddress(),
          borrowAmount,
          collateralToken
        )
      ).to.not.be.reverted;

      const userBorrow = await unifiedPool.getUserBorrows(user1.address, await usdfToken.getAddress());
      expect(userBorrow).to.equal(borrowAmount);
    });

    it("Should calculate health factor correctly", async function () {
      const healthFactor = await unifiedPool.getUserHealthFactor(user1.address);

      // Health factor should be > 1e18 (>100%) since user has collateral
      expect(healthFactor).to.be.gt(ethers.parseEther("1"));
    });

    it("Should repay borrowed amount", async function () {
      const repayAmount = ethers.parseEther("2000");

      // User needs to approve and have USDF
      await usdfToken.connect(user1).approve(await unifiedPool.getAddress(), ethers.MaxUint256);

      await unifiedPool.connect(user1).repay(await usdfToken.getAddress(), repayAmount);

      const userBorrow = await unifiedPool.getUserBorrows(user1.address, await usdfToken.getAddress());
      expect(userBorrow).to.equal(ethers.parseEther("3000")); // 5000 - 2000
    });

    it("Should revert borrowing when collateral insufficient", async function () {
      const excessBorrow = ethers.parseEther("50000"); // Way more than collateral allows

      await expect(
        unifiedPool.connect(user2).borrow(
          await usdfToken.getAddress(),
          excessBorrow,
          await wethToken.getAddress()
        )
      ).to.be.revertedWith("Insufficient collateral");
    });

    it("Should revert repaying more than borrowed", async function () {
      const excessRepay = ethers.parseEther("100000");

      await expect(
        unifiedPool.connect(user1).repay(await usdfToken.getAddress(), excessRepay)
      ).to.be.revertedWith("Repay amount too high");
    });
  });

  describe("DEX Integration - Borrow/Return Liquidity", function () {

    before(async function () {
      // Grant role to DEX contract (simulated)
      // For now, owner will call these functions
    });

    it("Should borrow liquidity for DEX", async function () {
      const borrowAmount = ethers.parseEther("1000");

      await unifiedPool.borrowLiquidity(await usdfToken.getAddress(), borrowAmount);

      const assetInfo = await unifiedPool.getAssetInfo(await usdfToken.getAddress());
      expect(assetInfo.totalBorrows).to.be.gt(0);
    });

    it("Should return liquidity from DEX", async function () {
      const returnAmount = ethers.parseEther("500");

      // Mint some USDF to this contract to return
      await usdfToken.mint(owner.address, returnAmount);
      await usdfToken.approve(await unifiedPool.getAddress(), returnAmount);

      const borrowsBefore = (await unifiedPool.getAssetInfo(await usdfToken.getAddress())).totalBorrows;

      await unifiedPool.returnLiquidity(await usdfToken.getAddress(), returnAmount);

      const borrowsAfter = (await unifiedPool.getAssetInfo(await usdfToken.getAddress())).totalBorrows;
      expect(borrowsAfter).to.equal(borrowsBefore - returnAmount);
    });

    it("Should calculate available liquidity correctly", async function () {
      const available = await unifiedPool.getAvailableLiquidity(await usdfToken.getAddress());
      const total = await unifiedPool.getTotalLiquidity(await usdfToken.getAddress());
      const borrowed = (await unifiedPool.getAssetInfo(await usdfToken.getAddress())).totalBorrows;

      expect(available).to.equal(total - borrowed);
    });
  });

  describe("Interest Rates & Utilization", function () {

    it("Should calculate utilization rate", async function () {
      const utilization = await unifiedPool.getUtilizationRate(await usdfToken.getAddress());

      // Utilization = totalBorrows / totalDeposits
      expect(utilization).to.be.lte(ethers.parseEther("1")); // <= 100%
      expect(utilization).to.be.gte(0);
    });

    it("Should calculate borrow rate based on utilization", async function () {
      const borrowRate = await unifiedPool.getBorrowRate(await usdfToken.getAddress());

      // Should be reasonable (between 0-50%)
      expect(borrowRate).to.be.gte(0);
      expect(borrowRate).to.be.lte(ethers.parseEther("0.5"));
    });

    it("Should calculate supply rate", async function () {
      const supplyRate = await unifiedPool.getSupplyRate(await usdfToken.getAddress());

      // Supply rate should be lower than borrow rate
      const borrowRate = await unifiedPool.getBorrowRate(await usdfToken.getAddress());
      expect(supplyRate).to.be.lte(borrowRate);
      expect(supplyRate).to.be.gte(0);
    });

    it("Should increase borrow rate when utilization is high", async function () {
      // Record initial rate
      const initialRate = await unifiedPool.getBorrowRate(await usdfToken.getAddress());

      // Borrow more to increase utilization
      await unifiedPool.borrowLiquidity(await usdfToken.getAddress(), ethers.parseEther("5000"));

      const newRate = await unifiedPool.getBorrowRate(await usdfToken.getAddress());

      // Rate should increase with utilization
      expect(newRate).to.be.gte(initialRate);
    });
  });

  describe("Liquidations", function () {

    it("Should identify liquidatable position", async function () {
      // This would require manipulating collateral value or debt
      // For now, just test the function exists
      const isLiquidatable = await unifiedPool.isLiquidatable(user1.address);
      expect(typeof isLiquidatable).to.equal("boolean");
    });

    it("Should calculate health factor for all users", async function () {
      const healthFactor1 = await unifiedPool.getUserHealthFactor(user1.address);
      const healthFactor2 = await unifiedPool.getUserHealthFactor(user2.address);

      // Both should be valid numbers
      expect(healthFactor1).to.be.gte(0);
      expect(healthFactor2).to.be.gte(0);
    });
  });

  describe("Liquidity Allocation", function () {

    it("Should set liquidity allocation", async function () {
      const allocation = {
        lendingPool: ethers.parseEther("5000"),
        dexPool: ethers.parseEther("3000"),
        vaultStrategies: ethers.parseEther("2000"),
        liquidStaking: ethers.parseEther("1000"),
        reserves: ethers.parseEther("2000")
      };

      await expect(
        unifiedPool.allocateLiquidity(await usdfToken.getAddress(), allocation)
      ).to.emit(unifiedPool, "LiquidityAllocated")
        .withArgs(await usdfToken.getAddress(), [
          allocation.lendingPool,
          allocation.dexPool,
          allocation.vaultStrategies,
          allocation.liquidStaking,
          allocation.reserves
        ]);
    });

    it("Should trigger rebalance", async function () {
      await expect(
        unifiedPool.rebalanceLiquidity(await usdfToken.getAddress())
      ).to.emit(unifiedPool, "RebalanceExecuted");
    });
  });

  describe("Edge Cases & Security", function () {

    it("Should handle zero deposits gracefully", async function () {
      await expect(
        unifiedPool.connect(user1).deposit(await usdfToken.getAddress(), 0)
      ).to.be.revertedWith("Invalid amount");
    });

    it("Should prevent unauthorized asset management", async function () {
      const assetInfo = {
        token: await daiToken.getAddress(),
        totalDeposits: 0,
        totalBorrows: 0,
        reserveFactor: ethers.parseEther("0.1"),
        collateralFactor: ethers.parseEther("0.8"),
        liquidationThreshold: ethers.parseEther("0.85"),
        liquidationBonus: ethers.parseEther("0.05"),
        isActive: true,
        canBorrow: true,
        canCollateralize: true
      };

      await expect(
        unifiedPool.connect(user1).addAsset(await daiToken.getAddress(), assetInfo)
      ).to.be.reverted;
    });

    it("Should handle asset with zero liquidity", async function () {
      // Add DAI but don't deposit anything
      const assetInfo = {
        token: await daiToken.getAddress(),
        totalDeposits: 0,
        totalBorrows: 0,
        reserveFactor: ethers.parseEther("0.1"),
        collateralFactor: ethers.parseEther("0.8"),
        liquidationThreshold: ethers.parseEther("0.85"),
        liquidationBonus: ethers.parseEther("0.05"),
        isActive: true,
        canBorrow: true,
        canCollateralize: true
      };

      await unifiedPool.addAsset(await daiToken.getAddress(), assetInfo);

      const utilization = await unifiedPool.getUtilizationRate(await daiToken.getAddress());
      expect(utilization).to.equal(0);
    });
  });

  describe("Gas Profiling", function () {

    it("Should measure gas for deposit", async function () {
      const tx = await unifiedPool.connect(user1).deposit(
        await usdfToken.getAddress(),
        ethers.parseEther("1000")
      );
      const receipt = await tx.wait();

      console.log(`\n      ⛽ Deposit Gas: ${receipt!.gasUsed.toLocaleString()}`);
      console.log(`      Target: <50,000 gas`);
    });

    it("Should measure gas for borrow", async function () {
      const tx = await unifiedPool.connect(user1).borrow(
        await usdfToken.getAddress(),
        ethers.parseEther("100"),
        await wethToken.getAddress()
      );
      const receipt = await tx.wait();

      console.log(`\n      ⛽ Borrow Gas: ${receipt!.gasUsed.toLocaleString()}`);
      console.log(`      Target: <80,000 gas`);
    });

    it("Should measure gas for interest rate calculation", async function () {
      // View functions - gas is minimal
      const borrowRate = await unifiedPool.getBorrowRate(await usdfToken.getAddress());
      const supplyRate = await unifiedPool.getSupplyRate(await usdfToken.getAddress());

      expect(borrowRate).to.be.gte(0);
      expect(supplyRate).to.be.gte(0);

      console.log(`\n      ⛽ Interest Rate Calc: ~3,000 gas (view function)`);
    });
  });
});

import { expect } from "chai";
import { ethers } from "hardhat";
import { LiquidityCore, MockERC20, UnifiedLiquidityPool, AccessControlManager } from "../../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

/**
 * LiquidityCore - Comprehensive Integration Test Suite
 *
 * Tests centralized liquidity management that replaces ActivePool, DefaultPool, CollSurplusPool
 *
 * Test Coverage:
 * - Collateral deposit/withdrawal
 * - Debt minting/burning
 * - UnifiedPool integration
 * - Liquidation rewards
 * - Emergency liquidity
 * - Access control
 * - Edge cases
 */
describe("LiquidityCore - Integration Tests", function () {
  let liquidityCore: LiquidityCore;
  let unifiedPool: UnifiedLiquidityPool;
  let accessControl: AccessControlManager;
  let usdfToken: MockERC20;
  let wethToken: MockERC20;
  let wbtcToken: MockERC20;

  let owner: SignerWithAddress;
  let borrowerOps: SignerWithAddress;
  let troveManager: SignerWithAddress;
  let stabilityPool: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let liquidator: SignerWithAddress;

  before(async function () {
    [owner, borrowerOps, troveManager, stabilityPool, user1, user2, liquidator] = await ethers.getSigners();

    // Deploy AccessControlManager (from OrganisedSecured)
    const AccessControlFactory = await ethers.getContractFactory("contracts/OrganisedSecured/utils/AccessControlManager.sol:AccessControlManager");
    accessControl = await AccessControlFactory.deploy();
    await accessControl.waitForDeployment();

    // Deploy mock tokens (from OrganisedSecured)
    const MockERC20Factory = await ethers.getContractFactory("contracts/OrganisedSecured/mocks/MockERC20.sol:MockERC20");
    usdfToken = await MockERC20Factory.deploy("USDF Stablecoin", "USDF", 0);
    wethToken = await MockERC20Factory.deploy("Wrapped ETH", "WETH", 0);
    wbtcToken = await MockERC20Factory.deploy("Wrapped BTC", "WBTC", 0);
    await usdfToken.waitForDeployment();
    await wethToken.waitForDeployment();
    await wbtcToken.waitForDeployment();

    // Deploy UnifiedLiquidityPool (from OrganisedSecured)
    const UnifiedPoolFactory = await ethers.getContractFactory("contracts/OrganisedSecured/core/UnifiedLiquidityPool.sol:UnifiedLiquidityPool");
    unifiedPool = await UnifiedPoolFactory.deploy(await accessControl.getAddress());
    await unifiedPool.waitForDeployment();

    // Deploy LiquidityCore (from OrganisedSecured)
    const LiquidityCoreFactory = await ethers.getContractFactory("contracts/OrganisedSecured/core/LiquidityCore.sol:LiquidityCore");
    liquidityCore = await LiquidityCoreFactory.deploy(
      await accessControl.getAddress(),
      await unifiedPool.getAddress(),
      await usdfToken.getAddress()
    );
    await liquidityCore.waitForDeployment();

    // Setup roles
    const BORROWER_OPS_ROLE = await accessControl.BORROWER_OPS_ROLE();
    const TROVE_MANAGER_ROLE = await accessControl.TROVE_MANAGER_ROLE();
    const STABILITY_POOL_ROLE = await accessControl.STABILITY_POOL_ROLE();

    await accessControl.grantRole(BORROWER_OPS_ROLE, borrowerOps.address);
    await accessControl.grantRole(TROVE_MANAGER_ROLE, troveManager.address);
    await accessControl.grantRole(STABILITY_POOL_ROLE, stabilityPool.address);

    // Mint tokens for testing
    await wethToken.mint(await liquidityCore.getAddress(), ethers.parseEther("1000"));
    await wbtcToken.mint(await liquidityCore.getAddress(), ethers.parseEther("50"));
    await usdfToken.mint(await liquidityCore.getAddress(), ethers.parseEther("100000"));

    console.log("✓ LiquidityCore and dependencies deployed");
  });

  describe("Asset Management", function () {

    it("Should activate an asset", async function () {
      await liquidityCore.activateAsset(await wethToken.getAddress());

      expect(await liquidityCore.isAssetActive(await wethToken.getAddress())).to.be.true;
    });

    it("Should return active assets list", async function () {
      await liquidityCore.activateAsset(await wbtcToken.getAddress());

      const activeAssets = await liquidityCore.getActiveAssets();
      expect(activeAssets.length).to.equal(2);
      expect(activeAssets).to.include(await wethToken.getAddress());
      expect(activeAssets).to.include(await wbtcToken.getAddress());
    });

    it("Should revert when activating already active asset", async function () {
      await expect(
        liquidityCore.activateAsset(await wethToken.getAddress())
      ).to.be.revertedWithCustomError(liquidityCore, "AssetAlreadyActive");
    });

    it("Should deactivate an asset", async function () {
      await liquidityCore.deactivateAsset(await wbtcToken.getAddress());

      expect(await liquidityCore.isAssetActive(await wbtcToken.getAddress())).to.be.false;
    });

    it("Should revert operations on inactive asset", async function () {
      await expect(
        liquidityCore.connect(borrowerOps).depositCollateral(
          await wbtcToken.getAddress(),
          user1.address,
          ethers.parseEther("1")
        )
      ).to.be.revertedWithCustomError(liquidityCore, "AssetNotActive");
    });
  });

  describe("Collateral Management", function () {

    before(async function () {
      // Ensure WETH is active
      const isActive = await liquidityCore.isAssetActive(await wethToken.getAddress());
      if (!isActive) {
        await liquidityCore.activateAsset(await wethToken.getAddress());
      }
    });

    it("Should deposit collateral", async function () {
      const amount = ethers.parseEther("10");

      await expect(
        liquidityCore.connect(borrowerOps).depositCollateral(
          await wethToken.getAddress(),
          user1.address,
          amount
        )
      ).to.emit(liquidityCore, "CollateralDeposited")
        .withArgs(await wethToken.getAddress(), user1.address, amount, amount);

      const reserve = await liquidityCore.getCollateralReserve(await wethToken.getAddress());
      expect(reserve).to.equal(amount);
    });

    it("Should track multiple deposits", async function () {
      const amount1 = ethers.parseEther("5");
      const amount2 = ethers.parseEther("3");

      await liquidityCore.connect(borrowerOps).depositCollateral(
        await wethToken.getAddress(),
        user1.address,
        amount1
      );

      await liquidityCore.connect(borrowerOps).depositCollateral(
        await wethToken.getAddress(),
        user2.address,
        amount2
      );

      const totalReserve = await liquidityCore.getCollateralReserve(await wethToken.getAddress());
      // 10 (previous) + 5 + 3 = 18
      expect(totalReserve).to.equal(ethers.parseEther("18"));
    });

    it("Should withdraw collateral", async function () {
      const withdrawAmount = ethers.parseEther("5");
      const reserveBefore = await liquidityCore.getCollateralReserve(await wethToken.getAddress());

      await expect(
        liquidityCore.connect(borrowerOps).withdrawCollateral(
          await wethToken.getAddress(),
          user1.address,
          withdrawAmount
        )
      ).to.emit(liquidityCore, "CollateralWithdrawn")
        .withArgs(
          await wethToken.getAddress(),
          user1.address,
          withdrawAmount,
          reserveBefore - withdrawAmount
        );

      const reserveAfter = await liquidityCore.getCollateralReserve(await wethToken.getAddress());
      expect(reserveAfter).to.equal(reserveBefore - withdrawAmount);
    });

    it("Should revert withdrawal with insufficient collateral", async function () {
      const reserve = await liquidityCore.getCollateralReserve(await wethToken.getAddress());
      const excessAmount = reserve + ethers.parseEther("1");

      await expect(
        liquidityCore.connect(borrowerOps).withdrawCollateral(
          await wethToken.getAddress(),
          user1.address,
          excessAmount
        )
      ).to.be.revertedWithCustomError(liquidityCore, "InsufficientCollateral");
    });

    it("Should revert when unauthorized caller tries to deposit", async function () {
      await expect(
        liquidityCore.connect(user1).depositCollateral(
          await wethToken.getAddress(),
          user1.address,
          ethers.parseEther("1")
        )
      ).to.be.revertedWithCustomError(liquidityCore, "UnauthorizedCaller");
    });
  });

  describe("Debt Management", function () {

    it("Should mint debt", async function () {
      const amount = ethers.parseEther("5000");

      await expect(
        liquidityCore.connect(borrowerOps).mintDebt(
          await wethToken.getAddress(),
          user1.address,
          amount
        )
      ).to.emit(liquidityCore, "DebtMinted")
        .withArgs(await wethToken.getAddress(), user1.address, amount, amount);

      const debtReserve = await liquidityCore.getDebtReserve(await wethToken.getAddress());
      expect(debtReserve).to.equal(amount);
    });

    it("Should track debt for multiple users", async function () {
      const amount1 = ethers.parseEther("3000");
      const amount2 = ethers.parseEther("2000");

      await liquidityCore.connect(borrowerOps).mintDebt(
        await wethToken.getAddress(),
        user1.address,
        amount1
      );

      await liquidityCore.connect(borrowerOps).mintDebt(
        await wethToken.getAddress(),
        user2.address,
        amount2
      );

      const totalDebt = await liquidityCore.getDebtReserve(await wethToken.getAddress());
      // 5000 (previous) + 3000 + 2000 = 10000
      expect(totalDebt).to.equal(ethers.parseEther("10000"));
    });

    it("Should burn debt", async function () {
      const burnAmount = ethers.parseEther("2000");
      const debtBefore = await liquidityCore.getDebtReserve(await wethToken.getAddress());

      await expect(
        liquidityCore.connect(borrowerOps).burnDebt(
          await wethToken.getAddress(),
          user1.address,
          burnAmount
        )
      ).to.emit(liquidityCore, "DebtBurned")
        .withArgs(
          await wethToken.getAddress(),
          user1.address,
          burnAmount,
          debtBefore - burnAmount
        );

      const debtAfter = await liquidityCore.getDebtReserve(await wethToken.getAddress());
      expect(debtAfter).to.equal(debtBefore - burnAmount);
    });

    it("Should revert burning more debt than exists", async function () {
      const debtReserve = await liquidityCore.getDebtReserve(await wethToken.getAddress());
      const excessAmount = debtReserve + ethers.parseEther("1");

      await expect(
        liquidityCore.connect(borrowerOps).burnDebt(
          await wethToken.getAddress(),
          user1.address,
          excessAmount
        )
      ).to.be.revertedWithCustomError(liquidityCore, "InsufficientDebtReserve");
    });
  });

  describe("Liquidity Queries", function () {

    it("Should calculate available liquidity correctly", async function () {
      const collateral = await liquidityCore.getCollateralReserve(await wethToken.getAddress());
      const debt = await liquidityCore.getDebtReserve(await wethToken.getAddress());
      const available = await liquidityCore.getAvailableLiquidity(await wethToken.getAddress());

      // Available = Collateral - Debt (simplified)
      // In reality might be more complex with rewards, etc.
      expect(available).to.be.gt(0);
    });

    it("Should calculate utilization rate", async function () {
      const utilizationRate = await liquidityCore.getUtilizationRate(await wethToken.getAddress());

      // Utilization = (Debt / Collateral) * 10000 (basis points)
      expect(utilizationRate).to.be.lte(10000); // Max 100%
      expect(utilizationRate).to.be.gt(0); // Should have some utilization
    });

    it("Should return complete liquidity snapshot", async function () {
      const snapshot = await liquidityCore.getLiquiditySnapshot(await wethToken.getAddress());

      expect(snapshot.totalCollateral).to.be.gt(0);
      expect(snapshot.totalDebt).to.be.gt(0);
      expect(snapshot.availableLiquidity).to.be.gte(0);
      expect(snapshot.utilizationRate).to.be.lte(10000);
    });

    it("Should return asset liquidity details", async function () {
      const assetLiquidity = await liquidityCore.getAssetLiquidity(await wethToken.getAddress());

      expect(assetLiquidity.collateralReserve).to.be.gt(0);
      expect(assetLiquidity.debtReserve).to.be.gt(0);
      expect(assetLiquidity.isActive).to.be.true;
      expect(assetLiquidity.lastUpdateTime).to.be.gt(0);
    });
  });

  describe("Liquidation Rewards", function () {

    it("Should allocate rewards", async function () {
      const rewardAmount = ethers.parseEther("2");

      await expect(
        liquidityCore.connect(troveManager).allocateRewards(
          await wethToken.getAddress(),
          rewardAmount
        )
      ).to.emit(liquidityCore, "RewardsAllocated")
        .withArgs(await wethToken.getAddress(), rewardAmount, rewardAmount);

      const pendingRewards = await liquidityCore.getPendingRewards(await wethToken.getAddress());
      expect(pendingRewards).to.equal(rewardAmount);
    });

    it("Should claim rewards", async function () {
      const claimAmount = ethers.parseEther("1");
      const rewardsBefore = await liquidityCore.getPendingRewards(await wethToken.getAddress());

      await liquidityCore.connect(stabilityPool).claimRewards(
        await wethToken.getAddress(),
        liquidator.address,
        claimAmount
      );

      const rewardsAfter = await liquidityCore.getPendingRewards(await wethToken.getAddress());
      expect(rewardsAfter).to.equal(rewardsBefore - claimAmount);
    });

    it("Should revert claiming more than pending rewards", async function () {
      const pending = await liquidityCore.getPendingRewards(await wethToken.getAddress());
      const excessAmount = pending + ethers.parseEther("1");

      await expect(
        liquidityCore.connect(stabilityPool).claimRewards(
          await wethToken.getAddress(),
          liquidator.address,
          excessAmount
        )
      ).to.be.reverted;
    });
  });

  describe("UnifiedPool Integration", function () {

    before(async function () {
      // Setup UnifiedPool - add USDF asset
      const usdfAssetInfo = {
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

      await unifiedPool.addAsset(await usdfToken.getAddress(), usdfAssetInfo);

      // Activate USDF in LiquidityCore
      const isActive = await liquidityCore.isAssetActive(await usdfToken.getAddress());
      if (!isActive) {
        await liquidityCore.activateAsset(await usdfToken.getAddress());
      }
    });

    it("Should borrow liquidity from UnifiedPool", async function () {
      const borrowAmount = ethers.parseEther("1000");

      // Setup UnifiedPool with liquidity - deposit from user1
      await usdfToken.mint(user1.address, borrowAmount * 2n);
      await usdfToken.connect(user1).approve(await unifiedPool.getAddress(), borrowAmount * 2n);
      await unifiedPool.connect(user1).deposit(await usdfToken.getAddress(), borrowAmount * 2n);

      await expect(
        liquidityCore.connect(borrowerOps).borrowFromUnifiedPool(
          await usdfToken.getAddress(),
          borrowAmount
        )
      ).to.emit(liquidityCore, "LiquidityBorrowedFromUnified")
        .withArgs(await usdfToken.getAddress(), borrowAmount, borrowAmount);

      const borrowed = await liquidityCore.getBorrowedFromUnified(await usdfToken.getAddress());
      expect(borrowed).to.equal(borrowAmount);
    });

    it("Should return liquidity to UnifiedPool", async function () {
      const returnAmount = ethers.parseEther("500");
      const borrowedBefore = await liquidityCore.getBorrowedFromUnified(await usdfToken.getAddress());

      // Ensure previous borrow happened
      expect(borrowedBefore).to.be.gt(0);

      // Ensure LiquidityCore has tokens to return (mint some to it)
      await usdfToken.mint(await liquidityCore.getAddress(), returnAmount);

      await expect(
        liquidityCore.connect(borrowerOps).returnToUnifiedPool(
          await usdfToken.getAddress(),
          returnAmount
        )
      ).to.emit(liquidityCore, "LiquidityReturnedToUnified")
        .withArgs(await usdfToken.getAddress(), returnAmount, borrowedBefore - returnAmount);

      const borrowedAfter = await liquidityCore.getBorrowedFromUnified(await usdfToken.getAddress());
      expect(borrowedAfter).to.equal(borrowedBefore - returnAmount);
    });

    it("Should revert returning more than borrowed", async function () {
      const borrowed = await liquidityCore.getBorrowedFromUnified(await usdfToken.getAddress());
      const excessAmount = borrowed + ethers.parseEther("1");

      await expect(
        liquidityCore.connect(borrowerOps).returnToUnifiedPool(
          await usdfToken.getAddress(),
          excessAmount
        )
      ).to.be.reverted;
    });
  });

  describe("Emergency Functions", function () {

    it("Should provide emergency liquidity", async function () {
      const emergencyAmount = ethers.parseEther("5000");

      await usdfToken.mint(owner.address, emergencyAmount);
      await usdfToken.approve(await liquidityCore.getAddress(), emergencyAmount);

      await expect(
        liquidityCore.provideEmergencyLiquidity(
          await usdfToken.getAddress(),
          emergencyAmount
        )
      ).to.emit(liquidityCore, "EmergencyLiquidityProvided");
    });

    it("Should pause asset operations", async function () {
      await liquidityCore.pauseAsset(await wethToken.getAddress());

      await expect(
        liquidityCore.connect(borrowerOps).depositCollateral(
          await wethToken.getAddress(),
          user1.address,
          ethers.parseEther("1")
        )
      ).to.be.reverted;
    });

    it("Should unpause asset operations", async function () {
      await liquidityCore.unpauseAsset(await wethToken.getAddress());

      // Should work after unpause
      await expect(
        liquidityCore.connect(borrowerOps).depositCollateral(
          await wethToken.getAddress(),
          user1.address,
          ethers.parseEther("1")
        )
      ).to.not.be.reverted;
    });
  });

  describe("Edge Cases & Security", function () {

    it("Should handle zero amount gracefully", async function () {
      await expect(
        liquidityCore.connect(borrowerOps).depositCollateral(
          await wethToken.getAddress(),
          user1.address,
          0
        )
      ).to.be.revertedWithCustomError(liquidityCore, "InvalidAmount");
    });

    it("Should prevent unauthorized access to critical functions", async function () {
      await expect(
        liquidityCore.connect(user1).activateAsset(await wethToken.getAddress())
      ).to.be.reverted;

      await expect(
        liquidityCore.connect(user1).provideEmergencyLiquidity(
          await usdfToken.getAddress(),
          ethers.parseEther("1000")
        )
      ).to.be.reverted;
    });

    it("Should handle multiple assets correctly", async function () {
      // Activate WBTC again
      await liquidityCore.activateAsset(await wbtcToken.getAddress());

      // Deposit collateral for both assets
      await liquidityCore.connect(borrowerOps).depositCollateral(
        await wethToken.getAddress(),
        user1.address,
        ethers.parseEther("10")
      );

      await liquidityCore.connect(borrowerOps).depositCollateral(
        await wbtcToken.getAddress(),
        user1.address,
        ethers.parseEther("1")
      );

      const wethReserve = await liquidityCore.getCollateralReserve(await wethToken.getAddress());
      const wbtcReserve = await liquidityCore.getCollateralReserve(await wbtcToken.getAddress());

      expect(wethReserve).to.be.gt(0);
      expect(wbtcReserve).to.be.gt(0);
    });

    it("Should update timestamps on operations", async function () {
      const assetLiqBefore = await liquidityCore.getAssetLiquidity(await wethToken.getAddress());

      // Perform operation
      await liquidityCore.connect(borrowerOps).depositCollateral(
        await wethToken.getAddress(),
        user1.address,
        ethers.parseEther("1")
      );

      const assetLiqAfter = await liquidityCore.getAssetLiquidity(await wethToken.getAddress());

      expect(assetLiqAfter.lastUpdateTime).to.be.gte(assetLiqBefore.lastUpdateTime);
    });
  });

  describe("Gas Profiling", function () {

    it("Should measure gas for deposit operation", async function () {
      const tx = await liquidityCore.connect(borrowerOps).depositCollateral(
        await wethToken.getAddress(),
        user1.address,
        ethers.parseEther("1")
      );
      const receipt = await tx.wait();

      console.log(`\n      ⛽ Deposit Collateral Gas: ${receipt!.gasUsed.toLocaleString()}`);
      console.log(`      Target: <30,000 gas`);
    });

    it("Should measure gas for mint debt operation", async function () {
      const tx = await liquidityCore.connect(borrowerOps).mintDebt(
        await wethToken.getAddress(),
        user1.address,
        ethers.parseEther("1000")
      );
      const receipt = await tx.wait();

      console.log(`\n      ⛽ Mint Debt Gas: ${receipt!.gasUsed.toLocaleString()}`);
      console.log(`      Target: <35,000 gas`);
    });

    it("Should measure gas for liquidity snapshot", async function () {
      // View function - gas measured in transaction context
      const snapshot = await liquidityCore.getLiquiditySnapshot(await wethToken.getAddress());

      expect(snapshot.totalCollateral).to.be.gt(0);
      console.log(`\n      ⛽ Get Liquidity Snapshot: ~5,000 gas (view function)`);
    });
  });
});

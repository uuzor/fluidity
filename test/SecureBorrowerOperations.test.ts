import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import {
  SecureBorrowerOperations,
  AccessControlManager,
  PriceOracle,
  USDF,
  ActivePool,
  DefaultPool,
  GasPool,
  CollSurplusPool,
  SortedTroves
} from "../typechain-types";
import { time, mine, mineUpTo } from "@nomicfoundation/hardhat-network-helpers";

describe("SecureBorrowerOperations", function () {
  let borrowerOperations: SecureBorrowerOperations;
  let accessControl: AccessControlManager;
  let priceOracle: PriceOracle;
  let usdfToken: USDF;
  let troveManager: any;
  let stabilityPool: any;
  let activePool: ActivePool;
  let defaultPool: DefaultPool;
  let gasPool: GasPool;
  let collSurplusPool: CollSurplusPool;
  let sortedTroves: SortedTroves;
  let mockChainlinkFeed: any;
  
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  
  const DECIMAL_PRECISION = ethers.parseEther("1");
  const MIN_COLLATERAL_RATIO = ethers.parseEther("1.35"); // 135%
  const MIN_NET_DEBT = ethers.parseEther("200"); // 200 USDF
  const GAS_COMPENSATION = ethers.parseEther("200"); // 200 USDF
  const BORROWING_FEE_FLOOR = ethers.parseEther("0.005"); // 0.5%
  const MAX_BORROWING_FEE = ethers.parseEther("0.05"); // 5%
  const ETH_PRICE = ethers.parseEther("2000"); // $2000 per ETH
  const MAX_TROVES_PER_USER = 10n;
  const MAX_COLLATERAL_AMOUNT = ethers.parseEther("10000"); // 10K ETH
  const MAX_DEBT_AMOUNT = ethers.parseEther("1000000"); // 1M USDF
  const MIN_ADJUSTMENT_AMOUNT = ethers.parseEther("1");
  
  beforeEach(async function () {
    [owner, user1, user2, feeRecipient] = await ethers.getSigners();
    
    // Deploy AccessControlManager
    const AccessControlManagerFactory = await ethers.getContractFactory("AccessControlManager");
    accessControl = await AccessControlManagerFactory.deploy();
    await accessControl.waitForDeployment();
    
    // Set fee recipient
    await accessControl.setFeeRecipient(feeRecipient.address);
    
    // Deploy USDF Token (mock)
    const USFDFactory = await ethers.getContractFactory("USDF");
    usdfToken = await USFDFactory.deploy();
    await usdfToken.waitForDeployment();
    
    // Deploy MockChainlinkFeed for ETH
    const MockChainlinkFeedFactory = await ethers.getContractFactory("MockChainlinkFeed");
    mockChainlinkFeed = await MockChainlinkFeedFactory.deploy(
      ETH_PRICE, // price in wei (2000 * 1e18)
      18 // decimals
    );
    await mockChainlinkFeed.waitForDeployment();
    
    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracleFactory.deploy();
    await priceOracle.waitForDeployment();
    
    // Add ETH oracle to PriceOracle
    await priceOracle.addOracle(
      ethers.ZeroAddress, // ETH
      mockChainlinkFeed.target,
      3600 // 1 hour heartbeat
    );
    
    // Deploy pool contracts
    const ActivePoolFactory = await ethers.getContractFactory("ActivePool");
    activePool = await ActivePoolFactory.deploy();
    await activePool.waitForDeployment();
    
    const DefaultPoolFactory = await ethers.getContractFactory("DefaultPool");
    defaultPool = await DefaultPoolFactory.deploy();
    await defaultPool.waitForDeployment();
    
    const GasPoolFactory = await ethers.getContractFactory("GasPool");
    gasPool = await GasPoolFactory.deploy();
    await gasPool.waitForDeployment();
    
    const CollSurplusPoolFactory = await ethers.getContractFactory("CollSurplusPool");
    collSurplusPool = await CollSurplusPoolFactory.deploy();
    await collSurplusPool.waitForDeployment();
    
    const SortedTrovesFactory = await ethers.getContractFactory("SortedTroves");
    sortedTroves = await SortedTrovesFactory.deploy();
    await sortedTroves.waitForDeployment();
    
    // Deploy mock contracts to avoid circular dependencies
    const MockStabilityPoolFactory = await ethers.getContractFactory("MockStabilityPool");
    stabilityPool = await MockStabilityPoolFactory.deploy();
    await stabilityPool.waitForDeployment();
    
    const MockTroveManagerFactory = await ethers.getContractFactory("MockTroveManager");
    troveManager = await MockTroveManagerFactory.deploy();
    await troveManager.waitForDeployment();
    
    // Deploy SecureBorrowerOperations with mock dependencies
    const BorrowerOperationsFactory = await ethers.getContractFactory("SecureBorrowerOperations");
    borrowerOperations = await BorrowerOperationsFactory.deploy(
      accessControl.target,
      troveManager.target,
      usdfToken.target,
      priceOracle.target,
      activePool.target,
      defaultPool.target,
      stabilityPool.target,
      gasPool.target,
      collSurplusPool.target,
      sortedTroves.target
    );
    await borrowerOperations.waitForDeployment();
    
    // Set up permissions
    await usdfToken.grantRole(await usdfToken.MINTER_ROLE(), borrowerOperations.target);
    await usdfToken.grantRole(await usdfToken.MINTER_ROLE(), owner.address);
    await usdfToken.grantRole(await usdfToken.BURNER_ROLE(), borrowerOperations.target);
    
    // Initialize sorted troves with proper setup
    await sortedTroves.setTroveManager(troveManager.target);
    await sortedTroves.setBorrowerOperations(borrowerOperations.target);
    await sortedTroves.setMaxSize(ethers.ZeroAddress, 10000);
  });
  
  describe("openTrove", function () {
    it("Should successfully open a trove with valid parameters", async function () {
      const collAmount = ethers.parseEther("2"); // 2 ETH
      const usdfAmount = ethers.parseEther("1000"); // 1000 USDF
      const maxFeePercentage = ethers.parseEther("0.05"); // 5%
      
      // Calculate expected ICR: (2 ETH * $2000) / (1000 + fee + gas compensation)
      const borrowingFee = (usdfAmount * BORROWING_FEE_FLOOR) / DECIMAL_PRECISION;
      const netDebt = usdfAmount + borrowingFee;
      const compositeDebt = netDebt + GAS_COMPENSATION;
      const expectedICR = (collAmount * ETH_PRICE) / compositeDebt;
      
      expect(expectedICR).to.be.greaterThan(MIN_COLLATERAL_RATIO);
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress, // ETH
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress, // upperHint
          ethers.ZeroAddress, // lowerHint
          { value: collAmount }
        )
      ).to.emit(borrowerOperations, "TroveOperationSecure")
        .withArgs(
          user1.address,
          ethers.ZeroAddress,
          0, // BorrowerOperation.openTrove
          collAmount,
          compositeDebt,
          anyValue, // gasUsed
          anyValue  // blockNumber
        );
      
      // Check user received USDF
      expect(await usdfToken.balanceOf(user1.address)).to.equal(usdfAmount);
      
      // Check fee recipient received borrowing fee
      expect(await usdfToken.balanceOf(feeRecipient.address)).to.equal(borrowingFee);
      
      // Check gas pool received gas compensation
      expect(await usdfToken.balanceOf(gasPool.target)).to.equal(GAS_COMPENSATION);
      
      // Check user trove count increased
      expect(await borrowerOperations.userTroveCount(user1.address)).to.equal(1);
    });
    
    it("Should revert if collateral ratio is too low", async function () {
      const collAmount = ethers.parseEther("1"); // 1 ETH
      const usdfAmount = ethers.parseEther("2000"); // 2000 USDF (too much debt)
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("ICR below minimum");
    });
    
    it("Should revert if net debt is too small", async function () {
      const collAmount = ethers.parseEther("1");
      const usdfAmount = ethers.parseEther("100"); // Below MIN_NET_DEBT
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("Net debt too small");
    });
    
    it("Should revert if borrowing fee exceeds maximum", async function () {
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.001"); // 0.1% (too low)
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("Fee exceeds maximum");
    });
    
    it("Should revert if trove already exists", async function () {
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      // First trove should succeed
      await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        maxFeePercentage,
        collAmount,
        usdfAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: collAmount }
      );
      
      // Second trove should fail
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("Trove already exists");
    });
    
    it("Should revert if ETH amount mismatch", async function () {
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: ethers.parseEther("1") } // Wrong ETH amount
        )
      ).to.be.revertedWith("Incorrect ETH amount");
    });
    
    it("Should prevent MEV attacks (one action per block)", async function () {
      const collAmount = ethers.parseEther("1");
      const usdfAmount = ethers.parseEther("500");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await ethers.provider.send("evm_setAutomine", [false]);

      // First transaction in the block should succeed
      await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        maxFeePercentage,
        collAmount,
        usdfAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: collAmount }
      );

      // Mint some USDF to user1 so they can close the trove later
      await usdfToken.mint(user1.address, ethers.parseEther("1000"));
      
      // Different user should be allowed in same block
      await expect(
        borrowerOperations.connect(user2).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.not.be.reverted;
      
      const closeTroveTx = borrowerOperations.connect(user1).closeTrove(ethers.ZeroAddress);

      await ethers.provider.send("evm_mine");
      await ethers.provider.send("evm_setAutomine", [true]);

      // But same user should be blocked from second action in same block
      await expect(
        closeTroveTx
      ).to.be.revertedWith("One action per block");
    });
    
    it("Should enforce minimum adjustment amounts", async function () {
      const collAmount = ethers.parseEther("0.5"); // Below MIN_ADJUSTMENT_AMOUNT
      const usdfAmount = ethers.parseEther("500");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("Collateral amount too small");
    });
    
    it("Should validate maximum fee percentage bounds", async function () {
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.1"); // 10% - above MAX_BORROWING_FEE
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("Max fee too high");
    });
    
    it("Should validate zero amounts appropriately", async function () {
      const maxFeePercentage = ethers.parseEther("0.05");
      
      // Zero collateral should fail
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          0,
          ethers.parseEther("1000"),
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: 0 }
        )
      ).to.be.reverted;
      
      // Zero debt should fail with specific message
      await expect(
        borrowerOperations.connect(user2).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          ethers.parseEther("2"),
          0,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: ethers.parseEther("2") }
        )
      ).to.be.revertedWith("Net debt too small");
    });
  });

  describe("closeTrove", function () {
    beforeEach(async function () {
      // Open a trove first
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");

      await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        maxFeePercentage,
        collAmount,
        usdfAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: collAmount }
      );
    });

    it("Should successfully close a trove", async function () {
      const borrowingFee = (ethers.parseEther("1000") * BORROWING_FEE_FLOOR) / DECIMAL_PRECISION;
      const netDebtToRepay = ethers.parseEther("1000") + borrowingFee;

      // Mint extra USDF to user1 to cover the fee for closing
      await usdfToken.mint(user1.address, borrowingFee);
      
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      
      await expect(
        borrowerOperations.connect(user1).closeTrove(ethers.ZeroAddress)
      ).to.emit(borrowerOperations, "TroveOperationSecure");
      
      // Check user trove count decreased
      expect(await borrowerOperations.userTroveCount(user1.address)).to.equal(0);

      // Check user got their collateral back (minus gas fees)
      const tx = await borrowerOperations.connect(user1).closeTrove(ethers.ZeroAddress);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(user1.address);
      expect(balanceAfter).to.be.closeTo(balanceBefore + ethers.parseEther("2") - gasUsed, ethers.parseEther("0.001"));

      // Check USDF was burned
      expect(await usdfToken.balanceOf(user1.address)).to.equal(0);
    });
    
    it("Should revert if trove is not active", async function () {
      await expect(
        borrowerOperations.connect(user1).closeTrove(ethers.ZeroAddress)
      ).to.be.revertedWith("Trove not active");
    });
    
    it("Should revert if user has insufficient USDF balance", async function () {
      // Transfer away all USDF
      await expect(
        borrowerOperations.connect(user1).closeTrove(ethers.ZeroAddress)
      ).to.be.reverted; // Should be reverted by ERC20's burn function due to insufficient balance
    });
  });
  
  describe("addColl", function () {
    beforeEach(async function () {
      // Open a trove first
      await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        ethers.parseEther("0.05"),
        ethers.parseEther("2"),
        ethers.parseEther("1000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: ethers.parseEther("2") }
      );
      
      // Move to next block to avoid MEV protection
      await mine(1);
    });
    
    it("Should successfully add collateral to existing trove", async function () {
      const addAmount = ethers.parseEther("1");
      
      await expect(
        borrowerOperations.connect(user1).addColl(
          ethers.ZeroAddress,
          addAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: addAmount }
        )
      ).to.emit(borrowerOperations, "TroveOperationSecure")
        .withArgs(
          user1.address,
          ethers.ZeroAddress,
          1, // BorrowerOperation.addColl
          addAmount,
          0, // No debt change
          anyValue, // gasUsed
          anyValue  // blockNumber
        );
    });
    
    it("Should revert if trove does not exist", async function () {
      const addAmount = ethers.parseEther("1");
      
      await expect(
        borrowerOperations.connect(user2).addColl(
          ethers.ZeroAddress,
          addAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: addAmount }
        )
      ).to.be.revertedWith("Trove not active");
    });
    
    it("Should enforce minimum collateral amount", async function () {
      const addAmount = ethers.parseEther("0.5"); // Below MIN_ADJUSTMENT_AMOUNT
      
      await expect(
        borrowerOperations.connect(user1).addColl(
          ethers.ZeroAddress,
          addAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: addAmount }
        )
      ).to.be.revertedWith("Collateral amount too small");
    });
  });
  
  describe("withdrawColl", function () {
    beforeEach(async function () {
      // Open a trove with extra collateral
      await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        ethers.parseEther("0.05"),
        ethers.parseEther("5"), // Extra collateral for withdrawal
        ethers.parseEther("1000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: ethers.parseEther("5") }
      );
      
      await mine(1);
    });
    
    it("Should successfully withdraw collateral while maintaining ICR", async function () {
      const withdrawAmount = ethers.parseEther("1");
      
      await expect(
        borrowerOperations.connect(user1).withdrawColl(
          ethers.ZeroAddress,
          withdrawAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress
        )
      ).to.emit(borrowerOperations, "TroveOperationSecure")
        .withArgs(
          user1.address,
          ethers.ZeroAddress,
          2, // BorrowerOperation.withdrawColl
          withdrawAmount,
          0, // No debt change
          anyValue,
          anyValue
        );
    });
    
    it("Should revert if withdrawal would drop ICR below minimum", async function () {
      const withdrawAmount = ethers.parseEther("4"); // Too much withdrawal
      
      await expect(
        borrowerOperations.connect(user1).withdrawColl(
          ethers.ZeroAddress,
          withdrawAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress
        )
      ).to.be.revertedWith("ICR below minimum");
    });
    
    it("Should revert if trove does not exist", async function () {
      await expect(
        borrowerOperations.connect(user2).withdrawColl(
          ethers.ZeroAddress,
          ethers.parseEther("1"),
          ethers.ZeroAddress,
          ethers.ZeroAddress
        )
      ).to.be.revertedWith("Trove not active");
    });
  });
  
  describe("withdrawUSDF", function () {
    beforeEach(async function () {
      // Open a trove with extra collateral for borrowing
      await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        ethers.parseEther("0.05"),
        ethers.parseEther("10"), // Large collateral for extra borrowing
        ethers.parseEther("1000"),
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: ethers.parseEther("10") }
      );
      
      await mine(1);
    });
    
    it("Should successfully withdraw additional USDF", async function () {
      const withdrawAmount = ethers.parseEther("500");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).withdrawUSDF(
          ethers.ZeroAddress,
          maxFeePercentage,
          withdrawAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress
        )
      ).to.emit(borrowerOperations, "TroveOperationSecure");
      
      // Check user received additional USDF
      expect(await usdfToken.balanceOf(user1.address)).to.be.greaterThan(ethers.parseEther("1000"));
    });
    
    it("Should revert if withdrawal would drop ICR below minimum", async function () {
      const withdrawAmount = ethers.parseEther("10000"); // Too much debt
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).withdrawUSDF(
          ethers.ZeroAddress,
          maxFeePercentage,
          withdrawAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress
        )
      ).to.be.revertedWith("ICR below minimum");
    });
    
    it("Should enforce minimum net debt requirements", async function () {
      const withdrawAmount = ethers.parseEther("50"); // Too small
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).withdrawUSDF(
          ethers.ZeroAddress,
          maxFeePercentage,
          withdrawAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress
        )
      ).to.be.revertedWith("Debt amount too small");
    });
  });
  
  describe("Security Features", function () {
    it("Should validate price freshness", async function () {
      // Set price to be stale (older than MAX_PRICE_AGE)
      await time.increase(3700); // More than 1 hour
      
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("Price too stale");
    });
    
    it("Should enforce maximum collateral and debt amounts", async function () {
      const maxCollateral = ethers.parseEther("10001"); // Exceeds MAX_COLLATERAL_AMOUNT
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          maxCollateral,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: maxCollateral }
        )
      ).to.be.revertedWith("Collateral amount too large");
      
      const maxDebt = ethers.parseEther("1000001"); // Exceeds MAX_DEBT_AMOUNT
      const collAmount = ethers.parseEther("1000"); // Large collateral to support debt
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          maxDebt,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.be.revertedWith("Debt amount too large");
    });
    
    it.skip("Should respect maximum troves per user", async function () {
      // This test is skipped because it requires multi-asset support to open multiple troves for a single user.
      // The current test setup only uses ETH (ethers.ZeroAddress).
      // The logic for this test would involve:
      // 1. Deploying multiple mock asset tokens.
      // 2. Adding them to the PriceOracle.
      // 3. Opening MAX_TROVES_PER_USER troves with different assets for the same user.
      // 4. Expecting the (MAX_TROVES_PER_USER + 1)-th trove opening to fail with "User has too many troves".
      expect(MAX_TROVES_PER_USER).to.equal(10n);
    });
    
    it("Should test contract pause functionality", async function () {
      // Grant pauser role to owner
      await accessControl.grantRole(await accessControl.PAUSER_ROLE(), owner.address);

      // Pause the contract
      await accessControl.pause();

      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      // Operations should fail when paused
      await expect(
        borrowerOperations.connect(user1).openTrove(ethers.ZeroAddress, maxFeePercentage, collAmount, usdfAmount, ethers.ZeroAddress, ethers.ZeroAddress, { value: collAmount })
      ).to.be.revertedWith("Pausable: paused");

      // Unpause the contract
      await accessControl.unpause();

      // Operations should succeed when not paused
      const collAmount2 = ethers.parseEther("2");
      const usdfAmount2 = ethers.parseEther("1000");
      const maxFeePercentage2 = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage2,
          collAmount2,
          usdfAmount2,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount2 }
        )
      ).to.not.be.reverted;
    });
    
    it("Should validate security modifiers are applied", async function () {
      // Test antiMEV modifier functionality  
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await borrowerOperations.connect(user2).openTrove(
        ethers.ZeroAddress,
        maxFeePercentage,
        collAmount,
        usdfAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: collAmount }
      );
      
      // Verify lastActionBlock was set (antiMEV protection)
      expect(await borrowerOperations.lastActionBlock(user2.address)).to.be.greaterThan(0);
    });
    
    it.skip("Should prevent re-entrancy attacks", async function () {
      // This test requires a malicious attacker contract to properly test re-entrancy.
      // The attacker contract would have a receive() or fallback() function
      // that calls back into SecureBorrowerOperations functions like withdrawColl.
      // Example flow:
      // 1. Attacker contract opens a trove.
      // 2. Attacker calls withdrawColl.
      // 3. SecureBorrowerOperations sends ETH to attacker contract.
      // 4. Attacker's receive() function is triggered, which calls withdrawColl again.
      // 5. The nonReentrant modifier should revert the second call.
    });
  });
  
  describe("Gas Optimization", function () {
    it("Should complete trove operations within reasonable gas limits", async function () {
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      const tx = await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        maxFeePercentage,
        collAmount,
        usdfAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: collAmount }
      );
      
      const receipt = await tx.wait();
      expect(receipt?.gasUsed).to.be.lessThan(600000); // Reasonable gas limit for complex operation
    });
    
    it("Should handle batch operations efficiently", async function () {
      // Test multiple sequential operations for gas efficiency
      const collAmount = ethers.parseEther("3");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      // Open trove
      const openTx = await borrowerOperations.connect(user1).openTrove(
        ethers.ZeroAddress,
        maxFeePercentage,
        collAmount,
        usdfAmount,
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: collAmount }
      );
      
      await mine(1); // Avoid MEV protection
      
      // Add collateral
      const addCollTx = await borrowerOperations.connect(user1).addColl(
        ethers.ZeroAddress,
        ethers.parseEther("1"),
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        { value: ethers.parseEther("1") }
      );
      
      await mine(1);
      
      const borrowingFee = (usdfAmount * BORROWING_FEE_FLOOR) / DECIMAL_PRECISION;
      await usdfToken.mint(user1.address, borrowingFee);
      // Close trove
      const closeTx = await borrowerOperations.connect(user1).closeTrove(ethers.ZeroAddress);
      
      // All operations should be reasonably gas-efficient
      const openReceipt = await openTx.wait();
      const addReceipt = await addCollTx.wait();
      const closeReceipt = await closeTx.wait(); 
      
      expect(openReceipt?.gasUsed).to.be.lessThan(600000);
      expect(addReceipt?.gasUsed).to.be.lessThan(300000);
      expect(closeReceipt?.gasUsed).to.be.lessThan(400000);
    });
    
    it("Should track gas usage in event emissions", async function () {
      const collAmount = ethers.parseEther("2");
      const usdfAmount = ethers.parseEther("1000");
      const maxFeePercentage = ethers.parseEther("0.05");
      
      await expect(
        borrowerOperations.connect(user1).openTrove(
          ethers.ZeroAddress,
          maxFeePercentage,
          collAmount,
          usdfAmount,
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          { value: collAmount }
        )
      ).to.emit(borrowerOperations, "TroveOperationSecure")
        .withArgs(
          user1.address,
          ethers.ZeroAddress,
          0, // openTrove operation
          collAmount,
          anyValue, // composite debt
          anyValue, // gasUsed should be > 0
          anyValue  // blockNumber
        );
    });
  });
  
});

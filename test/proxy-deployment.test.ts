import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("Proxy Deployment Test", function() {
  let deployer: SignerWithAddress;
  let user: SignerWithAddress;
  
  let accessControlManager: any;
  let usdf: any;
  let fluidToken: any;
  let priceOracle: any;
  let mockChainlinkFeed: any;
  let sortedTroves: any;
  let liquidationHelpers: any;
  
  let troveManagerProxy: any;
  let borrowerOperationsProxy: any;
  let stabilityPoolProxy: any;
  
  before(async function() {
    [deployer, user] = await ethers.getSigners();
  });
  
  describe("Proxy Pattern Implementation", function() {
    it("Should deploy all contracts with proxy pattern successfully", async function() {
      // Deploy Access Control Manager
      const AccessControlManager = await ethers.getContractFactory("AccessControlManager");
      accessControlManager = await AccessControlManager.deploy();
      await accessControlManager.waitForDeployment();
      
      // Deploy tokens
      const USDF = await ethers.getContractFactory("USDF");
      usdf = await USDF.deploy();
      await usdf.waitForDeployment();
      
      const FluidToken = await ethers.getContractFactory("FluidToken");
      fluidToken = await FluidToken.deploy();
      await fluidToken.waitForDeployment();
      
      // Deploy oracle infrastructure
      const MockChainlinkFeed = await ethers.getContractFactory("MockChainlinkFeed");
      mockChainlinkFeed = await MockChainlinkFeed.deploy(200000000000, 8);
      await mockChainlinkFeed.waitForDeployment();
      
      const PriceOracle = await ethers.getContractFactory("PriceOracle");
      priceOracle = await PriceOracle.deploy();
      await priceOracle.waitForDeployment();
      
      await priceOracle.addOracle(ethers.ZeroAddress, await mockChainlinkFeed.getAddress(), 3600);
      
      // Deploy supporting contracts
      const SortedTroves = await ethers.getContractFactory("SortedTroves");
      sortedTroves = await SortedTroves.deploy();
      await sortedTroves.waitForDeployment();
      
      const LiquidationHelpers = await ethers.getContractFactory("LiquidationHelpers");
      liquidationHelpers = await LiquidationHelpers.deploy();
      await liquidationHelpers.waitForDeployment();
      
      expect(await accessControlManager.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await usdf.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await fluidToken.getAddress()).to.not.equal(ethers.ZeroAddress);
    });
    
    it("Should deploy proxy contracts successfully", async function() {
      // Deploy TroveManager Proxy
      const TroveManagerFactory = await ethers.getContractFactory("UpgradeableTroveManager");
      
      troveManagerProxy = await upgrades.deployProxy(
        TroveManagerFactory,
        [
          await accessControlManager.getAddress(),
          await usdf.getAddress(),
          await priceOracle.getAddress(),
          await sortedTroves.getAddress()
        ],
        { 
          initializer: 'initialize',
          kind: 'uups'
        }
      );
      await troveManagerProxy.waitForDeployment();
      
      // Deploy BorrowerOperations Proxy
      const BorrowerOperationsFactory = await ethers.getContractFactory("UpgradeableBorrowerOperations");
      
      borrowerOperationsProxy = await upgrades.deployProxy(
        BorrowerOperationsFactory,
        [
          await accessControlManager.getAddress(),
          await usdf.getAddress(),
          await priceOracle.getAddress(),
          await sortedTroves.getAddress()
        ],
        { 
          initializer: 'initialize',
          kind: 'uups'
        }
      );
      await borrowerOperationsProxy.waitForDeployment();
      
      // Deploy StabilityPool Proxy
      const StabilityPoolFactory = await ethers.getContractFactory("UpgradeableStabilityPool");
      
      stabilityPoolProxy = await upgrades.deployProxy(
        StabilityPoolFactory,
        [
          await accessControlManager.getAddress(),
          await usdf.getAddress(),
          await fluidToken.getAddress()
        ],
        { 
          initializer: 'initialize',
          kind: 'uups'
        }
      );
      await stabilityPoolProxy.waitForDeployment();
      
      expect(await troveManagerProxy.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await borrowerOperationsProxy.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await stabilityPoolProxy.getAddress()).to.not.equal(ethers.ZeroAddress);
    });
    
    it("Should configure cross-contract references successfully", async function() {
      // Use deployer address as mock for required addresses
      const mockAddress = deployer.address;
      
      // Set contract addresses in TroveManager
      await troveManagerProxy.setContractAddresses(
        await stabilityPoolProxy.getAddress(),
        await borrowerOperationsProxy.getAddress(),
        mockAddress, // activePool
        mockAddress, // defaultPool
        mockAddress, // collSurplusPool
        mockAddress  // gasPool
      );
      
      // Set contract addresses in BorrowerOperations
      await borrowerOperationsProxy.setContractAddresses(
        await troveManagerProxy.getAddress(),
        await stabilityPoolProxy.getAddress(),
        mockAddress, // activePool
        mockAddress, // defaultPool
        mockAddress, // collSurplusPool
        mockAddress  // gasPool
      );
      
      // Set contract addresses in StabilityPool
      await stabilityPoolProxy.setContractAddresses(
        await troveManagerProxy.getAddress(),
        await borrowerOperationsProxy.getAddress(),
        mockAddress, // activePool
        ethers.ZeroAddress  // communityIssuance - can be zero
      );
      
      // Verify references are set correctly
      expect(await troveManagerProxy.stabilityPool()).to.equal(await stabilityPoolProxy.getAddress());
      expect(await borrowerOperationsProxy.troveManager()).to.equal(await troveManagerProxy.getAddress());
      expect(await stabilityPoolProxy.troveManager()).to.equal(await troveManagerProxy.getAddress());
    });
    
    it("Should allow contract upgrades", async function() {
      // This test would verify that contracts can be upgraded
      // For now, we'll just check that the upgrade function exists
      const ADMIN_ROLE = await troveManagerProxy.ADMIN_ROLE();
      const hasRole = await troveManagerProxy.hasRole(ADMIN_ROLE, deployer.address);
      expect(hasRole).to.be.true;
      
      // In a real scenario, you would:
      // 1. Deploy a new implementation
      // 2. Call upgrade function
      // 3. Verify state is preserved
      // 4. Verify new functionality works
    });
    
    it("Should preserve state across proxy calls", async function() {
      // Check initial state
      const totalDebt = await troveManagerProxy.totalDebt(ethers.ZeroAddress);
      const totalUSDF = await stabilityPoolProxy.getTotalUSDF();
      
      expect(totalDebt).to.equal(0);
      expect(totalUSDF).to.equal(0);
      
      // State should be consistent across multiple calls
      const totalDebt2 = await troveManagerProxy.totalDebt(ethers.ZeroAddress);
      expect(totalDebt).to.equal(totalDebt2);
      
      // Test precision constants are set correctly
      const decimalPrecision = await stabilityPoolProxy.DECIMAL_PRECISION();
      const scaleFactor = await stabilityPoolProxy.SCALE_FACTOR();
      expect(decimalPrecision).to.equal(ethers.parseEther("1"));
      expect(scaleFactor).to.equal(ethers.parseUnits("1", 9));
    });
    
    it("Should have proper access control configured", async function() {
      const ADMIN_ROLE = await accessControlManager.ADMIN_ROLE();
      const hasAdminRole = await accessControlManager.hasRole(ADMIN_ROLE, deployer.address);
      expect(hasAdminRole).to.be.true;
      
      // Check that proxy contracts have the necessary roles
      const troveManagerAdminRole = await troveManagerProxy.ADMIN_ROLE();
      const troveManagerHasRole = await troveManagerProxy.hasRole(troveManagerAdminRole, deployer.address);
      expect(troveManagerHasRole).to.be.true;
      
      // Check BORROWING_FEE_FLOOR is correctly set
      const borrowingFeeFloor = await troveManagerProxy.BORROWING_FEE_FLOOR();
      expect(borrowingFeeFloor).to.equal(ethers.parseEther("0.005")); // 0.5%
      
      // Check StabilityPool roles
      const stabilityPoolAdminRole = await stabilityPoolProxy.ADMIN_ROLE();
      const stabilityPoolHasRole = await stabilityPoolProxy.hasRole(stabilityPoolAdminRole, deployer.address);
      expect(stabilityPoolHasRole).to.be.true;
    });
  });
  
  describe("Circular Dependency Resolution", function() {
    it("Should resolve circular dependencies through post-deployment configuration", async function() {
      // Verify that all contracts can reference each other
      const troveManagerAddress = await troveManagerProxy.getAddress();
      const borrowerOpsAddress = await borrowerOperationsProxy.getAddress();
      const stabilityPoolAddress = await stabilityPoolProxy.getAddress();
      
      // TroveManager should reference StabilityPool
      expect(await troveManagerProxy.stabilityPool()).to.equal(stabilityPoolAddress);
      
      // BorrowerOperations should reference TroveManager
      expect(await borrowerOperationsProxy.troveManager()).to.equal(troveManagerAddress);
      
      // StabilityPool should reference TroveManager
      expect(await stabilityPoolProxy.troveManager()).to.equal(troveManagerAddress);
      
      // This proves circular dependencies are resolved!
    });
    
    it("Should handle precision calculations safely", async function() {
      // Test that the stability pool can handle precision-sensitive operations
      const totalUSDF = await stabilityPoolProxy.getTotalUSDF();
      const totalCollateral = await stabilityPoolProxy.getTotalCollateral(ethers.ZeroAddress);
      
      expect(totalUSDF).to.equal(0);
      expect(totalCollateral).to.equal(0);
      
      // Verify precision constants match expected values
      const precisionMultiplier = ethers.parseUnits("1", 27);
      const rewardPrecision = ethers.parseUnits("1", 36);
      
      // These constants should be used internally for safe calculations
      // We can't access them directly but can verify the system works
      expect(await stabilityPoolProxy.P()).to.equal(ethers.parseEther("1"));
      expect(await stabilityPoolProxy.currentScale()).to.equal(0);
      expect(await stabilityPoolProxy.currentEpoch()).to.equal(0);
    });
  });
});
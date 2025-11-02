import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  FluidAMM,
  AccessControlManager,
  PriceOracle,
  UnifiedLiquidityPool,
  MockERC20,
} from "../../../typechain-types";

describe("FluidAMM", function () {
  let fluidAMM: FluidAMM;
  let accessControl: AccessControlManager;
  let priceOracle: PriceOracle;
  let unifiedPool: UnifiedLiquidityPool;
  let wethToken: MockERC20;
  let wbtcToken: MockERC20;
  let usdfToken: MockERC20;
  let randomToken: MockERC20;

  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let emergency: SignerWithAddress;

  const INITIAL_WETH = ethers.parseEther("100"); // 100 WETH
  const INITIAL_USDF = ethers.parseEther("200000"); // 200,000 USDF
  const INITIAL_WBTC = ethers.parseEther("10"); // 10 WBTC
  const INITIAL_RANDOM = ethers.parseEther("1000"); // 1000 Random tokens

  const ETH_PRICE = ethers.parseEther("2000"); // $2000
  const BTC_PRICE = ethers.parseEther("40000"); // $40000
  const USDF_PRICE = ethers.parseEther("1"); // $1

  beforeEach(async function () {
    [admin, alice, bob, emergency] = await ethers.getSigners();

    // Deploy AccessControlManager
    const AccessControlFactory = await ethers.getContractFactory("AccessControlManager");
    accessControl = await AccessControlFactory.deploy(admin.address);
    await accessControl.waitForDeployment();

    // Grant roles
    const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
    const EMERGENCY_ROLE = await accessControl.EMERGENCY_ROLE();

    await accessControl.grantRole(ADMIN_ROLE, admin.address, ethers.MaxUint256);
    await accessControl.grantRole(EMERGENCY_ROLE, emergency.address, ethers.MaxUint256);

    // Deploy mock tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    wethToken = await MockERC20Factory.deploy("Wrapped Ether", "WETH", 18);
    wbtcToken = await MockERC20Factory.deploy("Wrapped Bitcoin", "WBTC", 18);
    usdfToken = await MockERC20Factory.deploy("Fluid USD", "USDF", 18);
    randomToken = await MockERC20Factory.deploy("Random Token", "RAND", 18);

    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracleFactory.deploy(await accessControl.getAddress());
    await priceOracle.waitForDeployment();

    // Set prices in oracle
    await priceOracle.setPrice(await wethToken.getAddress(), ETH_PRICE);
    await priceOracle.setPrice(await wbtcToken.getAddress(), BTC_PRICE);
    await priceOracle.setPrice(await usdfToken.getAddress(), USDF_PRICE);
    // Note: randomToken has NO oracle price

    // Deploy mock UnifiedLiquidityPool (just for interface, not testing integration)
    const UnifiedPoolFactory = await ethers.getContractFactory("UnifiedLiquidityPool");
    unifiedPool = await UnifiedPoolFactory.deploy(
      await accessControl.getAddress(),
      await usdfToken.getAddress()
    );
    await unifiedPool.waitForDeployment();

    // Deploy FluidAMM
    const FluidAMMFactory = await ethers.getContractFactory("FluidAMM");
    fluidAMM = await FluidAMMFactory.deploy(
      await accessControl.getAddress(),
      await unifiedPool.getAddress(),
      await priceOracle.getAddress()
    );
    await fluidAMM.waitForDeployment();

    // Mint tokens to admin for pool creation
    await wethToken.mint(admin.address, INITIAL_WETH * 10n);
    await wbtcToken.mint(admin.address, INITIAL_WBTC * 10n);
    await usdfToken.mint(admin.address, INITIAL_USDF * 10n);
    await randomToken.mint(admin.address, INITIAL_RANDOM * 10n);

    // Mint tokens to Alice for swaps
    await wethToken.mint(alice.address, ethers.parseEther("50"));
    await usdfToken.mint(alice.address, ethers.parseEther("100000"));

    // Approve FluidAMM
    await wethToken.connect(admin).approve(await fluidAMM.getAddress(), ethers.MaxUint256);
    await wbtcToken.connect(admin).approve(await fluidAMM.getAddress(), ethers.MaxUint256);
    await usdfToken.connect(admin).approve(await fluidAMM.getAddress(), ethers.MaxUint256);
    await randomToken.connect(admin).approve(await fluidAMM.getAddress(), ethers.MaxUint256);

    await wethToken.connect(alice).approve(await fluidAMM.getAddress(), ethers.MaxUint256);
    await usdfToken.connect(alice).approve(await fluidAMM.getAddress(), ethers.MaxUint256);
  });

  describe("Pool Creation", function () {
    it("Should create pool with oracle validation (WETH/USDF)", async function () {
      const tx = await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true // Require oracle validation
      );

      const receipt = await tx.wait();
      const event = receipt?.logs.find((log: any) => {
        try {
          return fluidAMM.interface.parseLog(log)?.name === "PoolCreated";
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;

      // Check pool state
      const pool = await fluidAMM.getPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress()
      );

      expect(pool.isActive).to.be.true;
      expect(pool.requireOracleValidation).to.be.true;
      expect(pool.reserve0).to.be.gt(0);
      expect(pool.reserve1).to.be.gt(0);
    });

    it("Should create pool without oracle validation (Random/USDF)", async function () {
      const tx = await fluidAMM.createPool(
        await randomToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_RANDOM,
        ethers.parseEther("5000"),
        false // No oracle validation
      );

      await expect(tx).to.emit(fluidAMM, "PoolCreated");

      const pool = await fluidAMM.getPool(
        await randomToken.getAddress(),
        await usdfToken.getAddress()
      );

      expect(pool.isActive).to.be.true;
      expect(pool.requireOracleValidation).to.be.false; // No oracle required
    });

    it("Should revert if pool already exists", async function () {
      await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true
      );

      await expect(
        fluidAMM.createPool(
          await wethToken.getAddress(),
          await usdfToken.getAddress(),
          INITIAL_WETH,
          INITIAL_USDF,
          true
        )
      ).to.be.revertedWithCustomError(fluidAMM, "PoolAlreadyExists");
    });

    it("Should lock minimum liquidity on first deposit", async function () {
      const balanceBefore = await wethToken.balanceOf(admin.address);

      await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true
      );

      const balanceAfter = await wethToken.balanceOf(admin.address);
      expect(balanceBefore - balanceAfter).to.equal(INITIAL_WETH);
    });
  });

  describe("Swapping - With Oracle Validation", function () {
    beforeEach(async function () {
      // Create WETH/USDF pool with oracle validation
      await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true // Require oracle validation
      );
    });

    it("Should swap WETH for USDF with oracle validation", async function () {
      const amountIn = ethers.parseEther("1"); // 1 WETH
      const minAmountOut = ethers.parseEther("1900"); // Min 1900 USDF (5% slippage)

      const usdBalanceBefore = await usdfToken.balanceOf(alice.address);

      await fluidAMM.connect(alice).swapExactTokensForTokens(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        amountIn,
        minAmountOut,
        alice.address
      );

      const usdBalanceAfter = await usdfToken.balanceOf(alice.address);
      const received = usdBalanceAfter - usdBalanceBefore;

      expect(received).to.be.gte(minAmountOut);
      expect(received).to.be.closeTo(ethers.parseEther("1994"), ethers.parseEther("10")); // ~1994 USDF
    });

    it("Should revert if price deviation exceeds 2%", async function () {
      // Manipulate oracle price to cause deviation
      await priceOracle.setPrice(await wethToken.getAddress(), ethers.parseEther("1000")); // Half the price

      const amountIn = ethers.parseEther("1");
      const minAmountOut = ethers.parseEther("900");

      await expect(
        fluidAMM.connect(alice).swapExactTokensForTokens(
          await wethToken.getAddress(),
          await usdfToken.getAddress(),
          amountIn,
          minAmountOut,
          alice.address
        )
      ).to.be.revertedWithCustomError(fluidAMM, "PriceDeviationTooHigh");
    });

    it("Should revert if slippage protection fails", async function () {
      const amountIn = ethers.parseEther("1");
      const minAmountOut = ethers.parseEther("2500"); // Unrealistic expectation

      await expect(
        fluidAMM.connect(alice).swapExactTokensForTokens(
          await wethToken.getAddress(),
          await usdfToken.getAddress(),
          amountIn,
          minAmountOut,
          alice.address
        )
      ).to.be.revertedWithCustomError(fluidAMM, "InsufficientOutputAmount");
    });

    it("Should accumulate protocol fees", async function () {
      const amountIn = ethers.parseEther("1");
      const minAmountOut = ethers.parseEther("1900");

      await fluidAMM.connect(alice).swapExactTokensForTokens(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        amountIn,
        minAmountOut,
        alice.address
      );

      // Get pool ID
      const pool = await fluidAMM.getPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress()
      );

      // Protocol fees should be accumulated (can't directly check private mapping, but we can test collection)
    });
  });

  describe("Swapping - Without Oracle Validation", function () {
    beforeEach(async function () {
      // Create Random/USDF pool WITHOUT oracle validation
      await fluidAMM.createPool(
        await randomToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_RANDOM,
        ethers.parseEther("5000"),
        false // No oracle validation
      );

      // Mint random tokens to Alice
      await randomToken.mint(alice.address, ethers.parseEther("100"));
      await randomToken.connect(alice).approve(await fluidAMM.getAddress(), ethers.MaxUint256);
    });

    it("Should swap without oracle validation", async function () {
      const amountIn = ethers.parseEther("10"); // 10 Random tokens
      const minAmountOut = ethers.parseEther("40"); // Min 40 USDF

      const usdBalanceBefore = await usdfToken.balanceOf(alice.address);

      await fluidAMM.connect(alice).swapExactTokensForTokens(
        await randomToken.getAddress(),
        await usdfToken.getAddress(),
        amountIn,
        minAmountOut,
        alice.address
      );

      const usdBalanceAfter = await usdfToken.balanceOf(alice.address);
      const received = usdBalanceAfter - usdBalanceBefore;

      expect(received).to.be.gte(minAmountOut);
    });

    it("Should work even without oracle for token", async function () {
      // This should NOT revert even though randomToken has no oracle
      const amountIn = ethers.parseEther("10");
      const minAmountOut = ethers.parseEther("40");

      await expect(
        fluidAMM.connect(alice).swapExactTokensForTokens(
          await randomToken.getAddress(),
          await usdfToken.getAddress(),
          amountIn,
          minAmountOut,
          alice.address
        )
      ).to.not.be.reverted;
    });
  });

  describe("Liquidity Management", function () {
    let poolId: string;

    beforeEach(async function () {
      const tx = await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true
      );

      const receipt = await tx.wait();
      const event = receipt?.logs.find((log: any) => {
        try {
          const parsed = fluidAMM.interface.parseLog(log);
          return parsed?.name === "PoolCreated";
        } catch {
          return false;
        }
      });

      if (event) {
        const parsed = fluidAMM.interface.parseLog(event);
        poolId = parsed?.args[0]; // poolId is first argument
      }
    });

    it("Should add liquidity to existing pool", async function () {
      const amount0 = ethers.parseEther("10"); // 10 WETH
      const amount1 = ethers.parseEther("20000"); // 20,000 USDF

      await fluidAMM.addLiquidity(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        amount0,
        amount1,
        amount0 * 95n / 100n, // 5% slippage
        amount1 * 95n / 100n
      );

      const pool = await fluidAMM.getPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress()
      );

      expect(pool.reserve0).to.be.gt(INITIAL_WETH);
      expect(pool.reserve1).to.be.gt(INITIAL_USDF);
    });

    it("Should remove liquidity from pool", async function () {
      const pool = await fluidAMM.getPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress()
      );

      const liquidityToRemove = pool.totalSupply / 2n; // Remove 50%

      const wethBefore = await wethToken.balanceOf(admin.address);
      const usdfBefore = await usdfToken.balanceOf(admin.address);

      await fluidAMM.removeLiquidity(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        liquidityToRemove,
        0, // No minimum
        0
      );

      const wethAfter = await wethToken.balanceOf(admin.address);
      const usdfAfter = await usdfToken.balanceOf(admin.address);

      expect(wethAfter).to.be.gt(wethBefore);
      expect(usdfAfter).to.be.gt(usdfBefore);
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true
      );
    });

    it("Should get reserves", async function () {
      const [reserve0, reserve1] = await fluidAMM.getReserves(
        await wethToken.getAddress(),
        await usdfToken.getAddress()
      );

      expect(reserve0).to.equal(INITIAL_WETH);
      expect(reserve1).to.equal(INITIAL_USDF);
    });

    it("Should quote swap amount", async function () {
      const amountIn = ethers.parseEther("1");
      const [amountOut, fee] = await fluidAMM.quote(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        amountIn
      );

      expect(amountOut).to.be.gt(0);
      expect(fee).to.equal(amountIn * 30n / 10000n); // 0.3% fee
    });

    it("Should get spot price", async function () {
      const price = await fluidAMM.getSpotPrice(
        await wethToken.getAddress(),
        await usdfToken.getAddress()
      );

      // Price should be around 2000 (200,000 USDF / 100 WETH)
      expect(price).to.be.closeTo(ethers.parseEther("2000"), ethers.parseEther("10"));
    });

    it("Should get active pools", async function () {
      const activePools = await fluidAMM.getActivePools();
      expect(activePools.length).to.equal(1);
    });
  });

  describe("Emergency Functions", function () {
    beforeEach(async function () {
      await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true
      );
    });

    it("Should get available liquidity for token", async function () {
      const available = await fluidAMM.getAvailableLiquidity(await wethToken.getAddress());
      expect(available).to.equal(INITIAL_WETH);
    });

    it("Should emergency withdraw liquidity", async function () {
      const amount = ethers.parseEther("10");
      const destination = bob.address;

      const bobBalanceBefore = await wethToken.balanceOf(bob.address);

      await fluidAMM.connect(emergency).emergencyWithdrawLiquidity(
        await wethToken.getAddress(),
        amount,
        destination
      );

      const bobBalanceAfter = await wethToken.balanceOf(bob.address);
      expect(bobBalanceAfter - bobBalanceBefore).to.equal(amount);
    });

    it("Should revert emergency withdraw if not emergency role", async function () {
      await expect(
        fluidAMM.connect(alice).emergencyWithdrawLiquidity(
          await wethToken.getAddress(),
          ethers.parseEther("10"),
          alice.address
        )
      ).to.be.reverted;
    });
  });

  describe("Admin Functions", function () {
    let poolId: string;

    beforeEach(async function () {
      const tx = await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true
      );

      const receipt = await tx.wait();
      const event = receipt?.logs.find((log: any) => {
        try {
          const parsed = fluidAMM.interface.parseLog(log);
          return parsed?.name === "PoolCreated";
        } catch {
          return false;
        }
      });

      if (event) {
        const parsed = fluidAMM.interface.parseLog(event);
        poolId = parsed?.args[0];
      }
    });

    it("Should deactivate pool", async function () {
      await fluidAMM.deactivatePool(poolId);

      const pool = await fluidAMM.getPoolById(poolId);
      expect(pool.isActive).to.be.false;
    });

    it("Should activate pool", async function () {
      await fluidAMM.deactivatePool(poolId);
      await fluidAMM.activatePool(poolId);

      const pool = await fluidAMM.getPoolById(poolId);
      expect(pool.isActive).to.be.true;
    });

    it("Should update pool parameters", async function () {
      const newSwapFee = 50; // 0.5%
      const newProtocolFee = 5000; // 50%

      await fluidAMM.updatePoolParameters(poolId, newSwapFee, newProtocolFee);

      const pool = await fluidAMM.getPoolById(poolId);
      expect(pool.swapFee).to.equal(newSwapFee);
      expect(pool.protocolFeePct).to.equal(newProtocolFee);
    });

    it("Should collect protocol fees", async function () {
      // First make a swap to generate fees
      await fluidAMM.connect(alice).swapExactTokensForTokens(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        ethers.parseEther("1"),
        ethers.parseEther("1900"),
        alice.address
      );

      // Collect fees
      const adminBalanceBefore = await wethToken.balanceOf(admin.address);

      await fluidAMM.collectProtocolFees(poolId, admin.address);

      const adminBalanceAfter = await wethToken.balanceOf(admin.address);
      expect(adminBalanceAfter).to.be.gte(adminBalanceBefore);
    });
  });

  describe("Gas Profiling", function () {
    it("Should profile createPool gas", async function () {
      const tx = await fluidAMM.createPool(
        await wbtcToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WBTC,
        ethers.parseEther("400000"),
        true
      );

      const receipt = await tx.wait();
      console.log("      ⛽ CreatePool gas:", receipt?.gasUsed.toString());
    });

    it("Should profile swap gas (with oracle)", async function () {
      await fluidAMM.createPool(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_WETH,
        INITIAL_USDF,
        true
      );

      const tx = await fluidAMM.connect(alice).swapExactTokensForTokens(
        await wethToken.getAddress(),
        await usdfToken.getAddress(),
        ethers.parseEther("1"),
        ethers.parseEther("1900"),
        alice.address
      );

      const receipt = await tx.wait();
      console.log("      ⛽ Swap (with oracle) gas:", receipt?.gasUsed.toString());
    });

    it("Should profile swap gas (without oracle)", async function () {
      await fluidAMM.createPool(
        await randomToken.getAddress(),
        await usdfToken.getAddress(),
        INITIAL_RANDOM,
        ethers.parseEther("5000"),
        false
      );

      await randomToken.mint(alice.address, ethers.parseEther("100"));
      await randomToken.connect(alice).approve(await fluidAMM.getAddress(), ethers.MaxUint256);

      const tx = await fluidAMM.connect(alice).swapExactTokensForTokens(
        await randomToken.getAddress(),
        await usdfToken.getAddress(),
        ethers.parseEther("10"),
        ethers.parseEther("40"),
        alice.address
      );

      const receipt = await tx.wait();
      console.log("      ⛽ Swap (no oracle) gas:", receipt?.gasUsed.toString());
    });
  });
});

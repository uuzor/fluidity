// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IFluidAMM
 * @notice Interface for Fluid Protocol's gas-optimized constant product AMM
 * @dev Implements x * y = k formula with protocol-owned liquidity (POL)
 *
 * Key Features:
 * - Protocol-owned liquidity (no user LP tokens)
 * - Multi-pool support (WETH/USDF, WETH/WBTC, etc.)
 * - 0.3% swap fee (0.17% to LPs, 0.13% to protocol)
 * - Integration with UnifiedLiquidityPool for emergency withdrawals
 * - Oracle-validated pricing
 * - Gas-optimized operations
 */
interface IFluidAMM {

    // ============ Structs ============

    /**
     * @dev Pool configuration and state
     * @param token0 First token in pair (lower address)
     * @param token1 Second token in pair (higher address)
     * @param reserve0 Current reserve of token0
     * @param reserve1 Current reserve of token1
     * @param kLast Constant product k from last liquidity event
     * @param totalSupply Total LP token supply for this pool
     * @param swapFee Swap fee in basis points (default 30 = 0.3%)
     * @param protocolFeePct Protocol fee percentage of swap fee (default 43.33% = 13/30)
     * @param isActive Whether pool is active
     * @param requireOracleValidation Whether to validate swap prices against oracle (2% max deviation)
     * @param lastUpdateTime Last update timestamp
     */
    struct Pool {
        address token0;
        address token1;
        uint128 reserve0;
        uint128 reserve1;
        uint256 kLast;
        uint256 totalSupply;
        uint16 swapFee;
        uint16 protocolFeePct;
        bool isActive;
        bool requireOracleValidation;
        uint32 lastUpdateTime;
    }

    /**
     * @dev Swap result data
     * @param amountIn Amount of input tokens
     * @param amountOut Amount of output tokens
     * @param fee Total fee charged
     * @param protocolFee Fee going to protocol
     * @param newReserve0 New reserve of token0
     * @param newReserve1 New reserve of token1
     */
    struct SwapResult {
        uint256 amountIn;
        uint256 amountOut;
        uint256 fee;
        uint256 protocolFee;
        uint256 newReserve0;
        uint256 newReserve1;
    }

    // ============ Events ============

    event PoolCreated(
        bytes32 indexed poolId,
        address indexed token0,
        address indexed token1,
        uint256 reserve0,
        uint256 reserve1,
        uint256 liquidity
    );

    event LiquidityAdded(
        bytes32 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event LiquidityRemoved(
        bytes32 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event Swap(
        bytes32 indexed poolId,
        address indexed sender,
        address indexed recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );

    event ProtocolFeeCollected(
        bytes32 indexed poolId,
        address indexed token,
        uint256 amount
    );

    event EmergencyWithdrawal(
        bytes32 indexed poolId,
        address indexed token,
        uint256 amount,
        address indexed destination
    );

    event PoolActivated(bytes32 indexed poolId);
    event PoolDeactivated(bytes32 indexed poolId);
    event PoolParametersUpdated(bytes32 indexed poolId, uint16 swapFee, uint16 protocolFeePct);

    // ============ Errors ============

    error PoolNotFound(bytes32 poolId);
    error PoolAlreadyExists(address token0, address token1);
    error PoolNotActive(bytes32 poolId);
    error InvalidTokenPair(address token0, address token1);
    error IdenticalAddresses();
    error ZeroAddress();
    error InsufficientLiquidity(uint256 available, uint256 required);
    error InsufficientAmount(uint256 amount);
    error InsufficientInputAmount();
    error InsufficientOutputAmount(uint256 amountOut, uint256 minAmountOut);
    error InvalidK();
    error InvalidReserves();
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error ExcessiveSlippage();
    error PriceDeviationTooHigh(uint256 ammPrice, uint256 oraclePrice, uint256 maxDeviation);
    error Overflow();

    // ============ Liquidity Management ============

    /**
     * @notice Create a new liquidity pool
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount0 Initial amount of token0
     * @param amount1 Initial amount of token1
     * @param requireOracleValidation Whether to require oracle price validation (for liquidation-critical pools)
     * @return poolId Unique pool identifier
     * @return liquidity LP tokens minted
     */
    function createPool(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        bool requireOracleValidation
    ) external returns (bytes32 poolId, uint256 liquidity);

    /**
     * @notice Add liquidity to existing pool
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @param amount0Min Minimum amount of token0 (slippage protection)
     * @param amount1Min Minimum amount of token1 (slippage protection)
     * @return amount0 Actual amount of token0 added
     * @return amount1 Actual amount of token1 added
     * @return liquidity LP tokens minted
     */
    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /**
     * @notice Remove liquidity from pool
     * @param token0 First token address
     * @param token1 Second token address
     * @param liquidity Amount of LP tokens to burn
     * @param amount0Min Minimum amount of token0 to receive
     * @param amount1Min Minimum amount of token1 to receive
     * @return amount0 Amount of token0 received
     * @return amount1 Amount of token1 received
     */
    function removeLiquidity(
        address token0,
        address token1,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 amount0, uint256 amount1);

    // ============ Swapping ============

    /**
     * @notice Swap exact amount of input tokens for output tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Exact amount of input tokens
     * @param minAmountOut Minimum amount of output tokens (slippage protection)
     * @param recipient Address to receive output tokens
     * @return amountOut Actual amount of output tokens received
     */
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /**
     * @notice Swap tokens for exact amount of output tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountOut Exact amount of output tokens desired
     * @param maxAmountIn Maximum amount of input tokens (slippage protection)
     * @param recipient Address to receive output tokens
     * @return amountIn Actual amount of input tokens used
     */
    function swapTokensForExactTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address recipient
    ) external returns (uint256 amountIn);

    // ============ View Functions ============

    /**
     * @notice Get pool by token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @return pool Pool data
     */
    function getPool(address token0, address token1) external view returns (Pool memory pool);

    /**
     * @notice Get pool by ID
     * @param poolId Pool identifier
     * @return pool Pool data
     */
    function getPoolById(bytes32 poolId) external view returns (Pool memory pool);

    /**
     * @notice Get reserves for a token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @return reserve0 Reserve of token0
     * @return reserve1 Reserve of token1
     */
    function getReserves(address token0, address token1)
        external
        view
        returns (uint256 reserve0, uint256 reserve1);

    /**
     * @notice Get amount of output tokens for exact input
     * @param amountIn Amount of input tokens
     * @param reserveIn Reserve of input token
     * @param reserveOut Reserve of output token
     * @return amountOut Amount of output tokens
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view returns (uint256 amountOut);

    /**
     * @notice Get amount of input tokens needed for exact output
     * @param amountOut Amount of output tokens desired
     * @param reserveIn Reserve of input token
     * @param reserveOut Reserve of output token
     * @return amountIn Amount of input tokens needed
     */
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view returns (uint256 amountIn);

    /**
     * @notice Calculate output amount for a swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return amountOut Estimated output amount
     * @return fee Total fee charged
     */
    function quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint256 fee);

    /**
     * @notice Get current spot price
     * @param token0 First token address
     * @param token1 Second token address
     * @return price Price of token0 in terms of token1 (scaled by 1e18)
     */
    function getSpotPrice(address token0, address token1)
        external
        view
        returns (uint256 price);

    /**
     * @notice Get all active pools
     * @return poolIds Array of active pool IDs
     */
    function getActivePools() external view returns (bytes32[] memory poolIds);

    // ============ Emergency Functions ============

    /**
     * @notice Emergency withdraw liquidity from AMM to UnifiedLiquidityPool
     * @dev Called by UnifiedLiquidityPool during cascading withdrawal
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     * @param destination Destination address
     */
    function emergencyWithdrawLiquidity(
        address token,
        uint256 amount,
        address destination
    ) external;

    /**
     * @notice Get available liquidity for a token across all pools
     * @param token Token address
     * @return total Total available liquidity
     */
    function getAvailableLiquidity(address token) external view returns (uint256 total);

    // ============ Admin Functions ============

    /**
     * @notice Activate a pool
     * @param poolId Pool identifier
     */
    function activatePool(bytes32 poolId) external;

    /**
     * @notice Deactivate a pool
     * @param poolId Pool identifier
     */
    function deactivatePool(bytes32 poolId) external;

    /**
     * @notice Update pool parameters
     * @param poolId Pool identifier
     * @param swapFee New swap fee in basis points
     * @param protocolFeePct New protocol fee percentage
     */
    function updatePoolParameters(
        bytes32 poolId,
        uint16 swapFee,
        uint16 protocolFeePct
    ) external;

    /**
     * @notice Collect accumulated protocol fees
     * @param poolId Pool identifier
     * @param recipient Address to receive fees
     */
    function collectProtocolFees(bytes32 poolId, address recipient) external;
}

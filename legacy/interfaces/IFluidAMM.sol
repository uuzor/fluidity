// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IFluidAMM
 * @dev Interface for the Fluid AMM that integrates with the unified liquidity pool
 */
interface IFluidAMM {
    struct PoolInfo {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalSupply;
        uint256 fee;
        bool isActive;
    }

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        address to;
        uint256 deadline;
    }

    struct AddLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
        uint256 deadline;
    }

    // Events
    event PoolCreated(address indexed tokenA, address indexed tokenB, address pool);
    event LiquidityAdded(address indexed user, address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(address indexed user, address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB, uint256 liquidity);
    event Swap(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event FeesCollected(address indexed tokenA, address indexed tokenB, uint256 feeA, uint256 feeB);

    // Pool Management
    function createPool(address tokenA, address tokenB, uint256 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB) external view returns (address pool);
    function getPoolInfo(address tokenA, address tokenB) external view returns (PoolInfo memory);
    function getAllPools() external view returns (address[] memory);

    // Liquidity Operations
    function addLiquidity(AddLiquidityParams calldata params) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function removeLiquidity(address tokenA, address tokenB, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256 amountA, uint256 amountB);

    // Swap Operations
    function swapExactTokensForTokens(SwapParams calldata params) external returns (uint256 amountOut);
    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address tokenIn, address tokenOut, address to, uint256 deadline) external returns (uint256 amountIn);
    
    // Quote Functions
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut);
    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256 amountIn);
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB);

    // Price & Reserves
    function getReserves(address tokenA, address tokenB) external view returns (uint256 reserveA, uint256 reserveB, uint256 blockTimestampLast);
    function getPrice(address tokenA, address tokenB) external view returns (uint256 price);
    
    // Fee Management
    function setFee(address tokenA, address tokenB, uint256 fee) external;
    function collectFees(address tokenA, address tokenB) external returns (uint256 feeA, uint256 feeB);
    
    // Integration with Unified Pool
    function syncWithUnifiedPool(address token) external;
    function getUnifiedPoolLiquidity(address token) external view returns (uint256);
}
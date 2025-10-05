// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IFluidAMM.sol";
import "../interfaces/IUnifiedLiquidityPool.sol";
import "../libraries/Math.sol";
import "./FluidLPToken.sol";

/**
 * @title FluidAMM
 * @dev Automated Market Maker integrated with unified liquidity pool
 */
contract FluidAMM is IFluidAMM, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MIN_LIQUIDITY = 1000;
    uint256 public constant MAX_FEE = 0.01e18; // 1%
    uint256 public constant FLASH_LOAN_FEE = 0.0009e18; // 0.09%

    // State variables
    mapping(bytes32 => address) public pools; // keccak256(tokenA, tokenB) => pool address
    mapping(address => PoolInfo) public poolInfo;
    mapping(address => mapping(address => uint256)) public userLPBalance;
    
    address[] public allPools;
    IUnifiedLiquidityPool public unifiedPool;
    
    // Fee collection
    mapping(address => uint256) public protocolFees;
    uint256 public protocolFeeRate = 0.05e18; // 5% of trading fees
    
    // Flash loan state
    mapping(address => bool) public flashLoanActive;
    
    // Events
    event FlashLoan(address indexed borrower, address indexed token, uint256 amount, uint256 fee);

    modifier validPool(address tokenA, address tokenB) {
        require(tokenA != tokenB, "Identical tokens");
        // Allow zero address for ETH
        _;
    }

    modifier poolExists(address tokenA, address tokenB) {
        require(getPool(tokenA, tokenB) != address(0), "Pool does not exist");
        _;
    }

    constructor(address _unifiedPool) Ownable(msg.sender) {
        unifiedPool = IUnifiedLiquidityPool(_unifiedPool);
    }

    /**
     * @dev Create a new liquidity pool
     */
    function createPool(address tokenA, address tokenB, uint256 fee) 
        external 
        onlyOwner 
        validPool(tokenA, tokenB) 
        returns (address pool) 
    {
        require(fee <= MAX_FEE, "Fee too high");
        require(getPool(tokenA, tokenB) == address(0), "Pool already exists");
        
        // Order tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 poolKey = keccak256(abi.encodePacked(token0, token1));
        
        // Create LP token
        string memory name = string(abi.encodePacked("Fluid LP"));
        string memory symbol = string(abi.encodePacked("FLP"));
        
        pool = address(new FluidLPToken(name, symbol));
        pools[poolKey] = pool;
        allPools.push(pool);
        
        // Initialize pool info
        poolInfo[pool] = PoolInfo({
            tokenA: token0,
            tokenB: token1,
            reserveA: 0,
            reserveB: 0,
            totalSupply: 0,
            fee: fee,
            isActive: true
        });
        
        emit PoolCreated(token0, token1, pool);
        return pool;
    }

    /**
     * @dev Add liquidity to a pool
     */
    function addLiquidity(AddLiquidityParams calldata params) 
        external 
        nonReentrant 
        whenNotPaused 
        poolExists(params.tokenA, params.tokenB)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity) 
    {
        require(params.deadline >= block.timestamp, "Deadline expired");
        
        address pool = getPool(params.tokenA, params.tokenB);
        PoolInfo storage info = poolInfo[pool];
        
        // Calculate optimal amounts
        if (info.reserveA == 0 && info.reserveB == 0) {
            // First liquidity provision
            amountA = params.amountADesired;
            amountB = params.amountBDesired;
        } else {
            // Calculate proportional amounts
            uint256 amountBOptimal = quote(params.amountADesired, info.reserveA, info.reserveB);
            if (amountBOptimal <= params.amountBDesired) {
                require(amountBOptimal >= params.amountBMin, "Insufficient B amount");
                amountA = params.amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = quote(params.amountBDesired, info.reserveB, info.reserveA);
                require(amountAOptimal <= params.amountADesired && amountAOptimal >= params.amountAMin, "Insufficient A amount");
                amountA = amountAOptimal;
                amountB = params.amountBDesired;
            }
        }
        
        // Transfer tokens
        IERC20(info.tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(info.tokenB).safeTransferFrom(msg.sender, address(this), amountB);
        
        // Calculate liquidity tokens to mint
        if (info.totalSupply == 0) {
            liquidity = Math.sqrt(amountA * amountB) - MIN_LIQUIDITY;
            FluidLPToken(pool).mint(address(1), MIN_LIQUIDITY); // Lock minimum liquidity to address(1)
        } else {
            liquidity = Math.min(
                amountA.mulDiv(info.totalSupply, info.reserveA),
                amountB.mulDiv(info.totalSupply, info.reserveB)
            );
        }
        
        require(liquidity > 0, "Insufficient liquidity minted");
        
        // Update state
        info.reserveA += amountA;
        info.reserveB += amountB;
        info.totalSupply += liquidity;
        userLPBalance[msg.sender][pool] += liquidity;
        
        // Mint LP tokens - check for zero address
        require(params.to != address(0), "Invalid recipient");
        FluidLPToken(pool).mint(params.to, liquidity);
        
        emit LiquidityAdded(msg.sender, info.tokenA, info.tokenB, amountA, amountB, liquidity);
        
        // Sync with unified pool
        syncWithUnifiedPool(info.tokenA);
        syncWithUnifiedPool(info.tokenB);
    }

    /**
     * @dev Remove liquidity from a pool
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant whenNotPaused poolExists(tokenA, tokenB) returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "Deadline expired");
        
        address pool = getPool(tokenA, tokenB);
        PoolInfo storage info = poolInfo[pool];
        
        require(userLPBalance[msg.sender][pool] >= liquidity, "Insufficient LP balance");
        
        // Calculate amounts to return
        amountA = liquidity.mulDiv(info.reserveA, info.totalSupply);
        amountB = liquidity.mulDiv(info.reserveB, info.totalSupply);
        
        require(amountA >= amountAMin && amountB >= amountBMin, "Insufficient output amounts");
        
        // Update state
        userLPBalance[msg.sender][pool] -= liquidity;
        info.reserveA -= amountA;
        info.reserveB -= amountB;
        info.totalSupply -= liquidity;
        
        // Burn LP tokens
        FluidLPToken(pool).burn(msg.sender, liquidity);
        
        // Transfer tokens
        IERC20(info.tokenA).safeTransfer(to, amountA);
        IERC20(info.tokenB).safeTransfer(to, amountB);
        
        emit LiquidityRemoved(msg.sender, info.tokenA, info.tokenB, amountA, amountB, liquidity);
        
        // Sync with unified pool
        syncWithUnifiedPool(info.tokenA);
        syncWithUnifiedPool(info.tokenB);
    }

    /**
     * @dev Swap exact tokens for tokens
     */
    function swapExactTokensForTokens(SwapParams calldata params) 
        external 
        nonReentrant 
        whenNotPaused 
        poolExists(params.tokenIn, params.tokenOut)
        returns (uint256 amountOut) 
    {
        require(params.deadline >= block.timestamp, "Deadline expired");
        require(params.amountIn > 0, "Insufficient input amount");
        
        address pool = getPool(params.tokenIn, params.tokenOut);
        PoolInfo storage info = poolInfo[pool];
        
        // Calculate output amount
        amountOut = _getAmountOut(params.amountIn, params.tokenIn, params.tokenOut, info);
        require(amountOut >= params.amountOutMin, "Insufficient output amount");
        
        // Transfer input tokens
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        
        // Update reserves
        if (params.tokenIn == info.tokenA) {
            info.reserveA += params.amountIn;
            info.reserveB -= amountOut;
        } else {
            info.reserveB += params.amountIn;
            info.reserveA -= amountOut;
        }
        
        // Calculate and collect fees
        uint256 feeAmount = params.amountIn.mulDiv(info.fee, PRECISION);
        uint256 protocolFee = feeAmount.mulDiv(protocolFeeRate, PRECISION);
        protocolFees[params.tokenIn] += protocolFee;
        
        // Transfer output tokens
        IERC20(params.tokenOut).safeTransfer(params.to, amountOut);
        
        emit Swap(msg.sender, params.tokenIn, params.tokenOut, params.amountIn, amountOut);
        
        // Sync with unified pool
        syncWithUnifiedPool(params.tokenIn);
        syncWithUnifiedPool(params.tokenOut);
    }

    /**
     * @dev Swap tokens for exact tokens
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external nonReentrant whenNotPaused poolExists(tokenIn, tokenOut) returns (uint256 amountIn) {
        require(deadline >= block.timestamp, "Deadline expired");
        require(amountOut > 0, "Insufficient output amount");
        
        address pool = getPool(tokenIn, tokenOut);
        PoolInfo storage info = poolInfo[pool];
        
        // Calculate required input amount
        amountIn = _getAmountIn(amountOut, tokenIn, tokenOut, info);
        require(amountIn <= amountInMax, "Excessive input amount");
        
        // Transfer input tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Update reserves
        if (tokenIn == info.tokenA) {
            info.reserveA += amountIn;
            info.reserveB -= amountOut;
        } else {
            info.reserveB += amountIn;
            info.reserveA -= amountOut;
        }
        
        // Calculate and collect fees
        uint256 feeAmount = amountIn.mulDiv(info.fee, PRECISION);
        uint256 protocolFee = feeAmount.mulDiv(protocolFeeRate, PRECISION);
        protocolFees[tokenIn] += protocolFee;
        
        // Transfer output tokens
        IERC20(tokenOut).safeTransfer(to, amountOut);
        
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        
        // Sync with unified pool
        syncWithUnifiedPool(tokenIn);
        syncWithUnifiedPool(tokenOut);
    }

    /**
     * @dev Flash loan function
     */
    function flashLoan(address token, uint256 amount, bytes calldata data) external nonReentrant {
        require(!flashLoanActive[msg.sender], "Flash loan already active");
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient liquidity");
        
        uint256 fee = amount.mulDiv(FLASH_LOAN_FEE, PRECISION);
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        
        flashLoanActive[msg.sender] = true;
        
        // Transfer tokens to borrower
        IERC20(token).safeTransfer(msg.sender, amount);
        
        // Call borrower's callback
        IFlashLoanReceiver(msg.sender).executeOperation(token, amount, fee, data);
        
        // Check repayment
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "Flash loan not repaid");
        
        flashLoanActive[msg.sender] = false;
        protocolFees[token] += fee;
        
        emit FlashLoan(msg.sender, token, amount, fee);
    }

    // View functions
    function getPool(address tokenA, address tokenB) public view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return pools[keccak256(abi.encodePacked(token0, token1))];
    }

    function getPoolInfo(address tokenA, address tokenB) external view returns (PoolInfo memory) {
        address pool = getPool(tokenA, tokenB);
        return poolInfo[pool];
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) 
        external 
        view 
        poolExists(tokenIn, tokenOut)
        returns (uint256 amountOut) 
    {
        address pool = getPool(tokenIn, tokenOut);
        return _getAmountOut(amountIn, tokenIn, tokenOut, poolInfo[pool]);
    }

    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut) 
        external 
        view 
        poolExists(tokenIn, tokenOut)
        returns (uint256 amountIn) 
    {
        address pool = getPool(tokenIn, tokenOut);
        return _getAmountIn(amountOut, tokenIn, tokenOut, poolInfo[pool]);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) 
        public 
        pure 
        returns (uint256 amountB) 
    {
        require(amountA > 0, "Insufficient amount");
        require(reserveA > 0 && reserveB > 0, "Insufficient liquidity");
        return amountA.mulDiv(reserveB, reserveA);
    }

    function getReserves(address tokenA, address tokenB) 
        external 
        view 
        poolExists(tokenA, tokenB)
        returns (uint256 reserveA, uint256 reserveB, uint256 blockTimestampLast) 
    {
        address pool = getPool(tokenA, tokenB);
        PoolInfo memory info = poolInfo[pool];
        
        if (tokenA == info.tokenA) {
            return (info.reserveA, info.reserveB, block.timestamp);
        } else {
            return (info.reserveB, info.reserveA, block.timestamp);
        }
    }

    function getPrice(address tokenA, address tokenB) 
        external 
        view 
        poolExists(tokenA, tokenB)
        returns (uint256 price) 
    {
        address pool = getPool(tokenA, tokenB);
        PoolInfo memory info = poolInfo[pool];
        
        if (tokenA == info.tokenA) {
            return info.reserveB.mulDiv(PRECISION, info.reserveA);
        } else {
            return info.reserveA.mulDiv(PRECISION, info.reserveB);
        }
    }

    function getUnifiedPoolLiquidity(address token) external view returns (uint256) {
        return unifiedPool.getAvailableLiquidity(token);
    }

    // Internal functions
    function _getAmountOut(uint256 amountIn, address tokenIn, address tokenOut, PoolInfo memory info) 
        internal 
        pure 
        returns (uint256) 
    {
        require(amountIn > 0, "Insufficient input amount");
        
        uint256 reserveIn = tokenIn == info.tokenA ? info.reserveA : info.reserveB;
        uint256 reserveOut = tokenIn == info.tokenA ? info.reserveB : info.reserveA;
        
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        uint256 amountInWithFee = amountIn.mulDiv(PRECISION - info.fee, PRECISION);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithFee;
        
        return numerator / denominator;
    }

    function _getAmountIn(uint256 amountOut, address tokenIn, address tokenOut, PoolInfo memory info) 
        internal 
        pure 
        returns (uint256) 
    {
        require(amountOut > 0, "Insufficient output amount");
        
        uint256 reserveIn = tokenIn == info.tokenA ? info.reserveA : info.reserveB;
        uint256 reserveOut = tokenIn == info.tokenA ? info.reserveB : info.reserveA;
        
        require(reserveIn > 0 && reserveOut > amountOut, "Insufficient liquidity");
        
        uint256 numerator = reserveIn * amountOut;
        uint256 denominator = (reserveOut - amountOut).mulDiv(PRECISION - info.fee, PRECISION);
        
        return (numerator / denominator) + 1;
    }

    // Admin functions
    function setFee(address tokenA, address tokenB, uint256 fee) 
        external 
        onlyOwner 
        poolExists(tokenA, tokenB) 
    {
        require(fee <= MAX_FEE, "Fee too high");
        address pool = getPool(tokenA, tokenB);
        poolInfo[pool].fee = fee;
    }

    function collectFees(address tokenA, address tokenB) 
        external 
        onlyOwner 
        poolExists(tokenA, tokenB)
        returns (uint256 feeA, uint256 feeB) 
    {
        feeA = protocolFees[tokenA];
        feeB = protocolFees[tokenB];
        
        protocolFees[tokenA] = 0;
        protocolFees[tokenB] = 0;
        
        if (feeA > 0) IERC20(tokenA).safeTransfer(msg.sender, feeA);
        if (feeB > 0) IERC20(tokenB).safeTransfer(msg.sender, feeB);
        
        emit FeesCollected(tokenA, tokenB, feeA, feeB);
    }

    function syncWithUnifiedPool(address token) public {
        uint256 ammBalance = IERC20(token).balanceOf(address(this));
        uint256 unifiedLiquidity = unifiedPool.getAvailableLiquidity(token);

        // If AMM needs more liquidity, borrow from unified pool
        if (ammBalance < 1000e18 && unifiedLiquidity > 0) {
            uint256 borrowAmount = Math.min(unifiedLiquidity / 10, 500e18);
            unifiedPool.borrowLiquidity(token, borrowAmount);
        }

        // If AMM has excess liquidity, try to return to unified pool
        if (ammBalance > 2000e18) {
            uint256 returnAmount = ammBalance - 1500e18;
            IERC20(token).approve(address(unifiedPool), returnAmount);
            try unifiedPool.returnLiquidity(token, returnAmount) {
                // Successfully returned liquidity
            } catch {
                // Failed to return - likely no borrowed amount or insufficient borrows
                // Reset approval to 0 for security
                IERC20(token).approve(address(unifiedPool), 0);
            }
        }
    }

    function setProtocolFeeRate(uint256 _protocolFeeRate) external onlyOwner {
        require(_protocolFeeRate <= 0.2e18, "Fee rate too high"); // Max 20%
        protocolFeeRate = _protocolFeeRate;
    }

    function registerForSonicFeeM(uint256 projectId) external onlyOwner {
        (bool success,) = address(0xDC2B0D2Dd2b7759D97D50db4eabDC36973110830).call(
            abi.encodeWithSignature("selfRegister(uint256)", projectId)
        );
        require(success, "FeeM registration failed");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// Interface for flash loan receivers
interface IFlashLoanReceiver {
    function executeOperation(address token, uint256 amount, uint256 fee, bytes calldata data) external;
}
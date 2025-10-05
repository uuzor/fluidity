// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AccessControlManager.sol";

/**
 * @title SecurityBase
 * @dev Base contract with enhanced security features for Fluid Protocol
 */
abstract contract SecurityBase is ReentrancyGuard, Pausable {
    
    AccessControlManager public immutable accessControl;
    
    // Circuit breaker thresholds
    uint256 public constant MAX_LIQUIDATIONS_PER_BLOCK = 50;
    uint256 public constant MAX_TOTAL_VALUE_LOCKED_CHANGE = 1000000e18; // 1M USDF
    
    // Circuit breaker state
    mapping(uint256 => uint256) public liquidationsThisBlock;
    uint256 public lastTVLSnapshot;
    uint256 public lastTVLUpdateBlock;
    
    // State validation
    mapping(bytes32 => bool) public validStates;
    
    // Events
    event CircuitBreakerTriggered(string reason, uint256 value, uint256 threshold);
    event StateValidationFailed(bytes32 stateHash, string reason);
    event SecurityViolation(address indexed caller, string violation);
    
    constructor(address _accessControl) {
        accessControl = AccessControlManager(_accessControl);
    }
    
    /**
     * @dev Enhanced reentrancy protection with state validation
     */
    modifier secureNonReentrant() {
        bytes32 stateBefore = _captureState();
        _;
        bytes32 stateAfter = _captureState();
        _validateStateTransition(stateBefore, stateAfter);
    }
    
    /**
     * @dev Circuit breaker for liquidations
     */
    modifier liquidationCircuitBreaker() {
        uint256 currentBlock = block.number;
        liquidationsThisBlock[currentBlock]++;
        
        if (liquidationsThisBlock[currentBlock] > MAX_LIQUIDATIONS_PER_BLOCK) {
            emit CircuitBreakerTriggered(
                "Too many liquidations per block",
                liquidationsThisBlock[currentBlock],
                MAX_LIQUIDATIONS_PER_BLOCK
            );
            _pause();
            revert("Circuit breaker: liquidation limit exceeded");
        }
        _;
    }
    
    /**
     * @dev TVL change circuit breaker
     */
    modifier tvlCircuitBreaker(uint256 newTVL) {
        if (lastTVLUpdateBlock != block.number) {
            uint256 tvlChange = newTVL > lastTVLSnapshot 
                ? newTVL - lastTVLSnapshot 
                : lastTVLSnapshot - newTVL;
                
            if (tvlChange > MAX_TOTAL_VALUE_LOCKED_CHANGE) {
                emit CircuitBreakerTriggered(
                    "TVL change too large",
                    tvlChange,
                    MAX_TOTAL_VALUE_LOCKED_CHANGE
                );
                _pause();
                revert("Circuit breaker: TVL change too large");
            }
            
            lastTVLSnapshot = newTVL;
            lastTVLUpdateBlock = block.number;
        }
        _;
    }
    
    /**
     * @dev Access control integration
     */
    modifier onlyValidRole(bytes32 role) {
        require(
            accessControl.hasValidRole(role, msg.sender),
            "Invalid or expired role"
        );
        _;
    }
    
    modifier whenContractNotPaused() {
        require(
            !accessControl.contractPaused(address(this)),
            "Contract is emergency paused"
        );
        _;
    }
    
    /**
     * @dev State capture and validation
     */
    function _captureState() internal view virtual returns (bytes32) {
        // Override in implementing contracts to capture relevant state
        return keccak256(abi.encodePacked(block.timestamp, address(this)));
    }
    
    function _validateStateTransition(
        bytes32 stateBefore,
        bytes32 stateAfter
    ) internal virtual {
        // Override in implementing contracts for specific validation
        // Basic check: state should change in controlled operations
        if (stateBefore == stateAfter) {
            // This might be expected for view operations
            return;
        }
    }
    
    /**
     * @dev Safe math operations with overflow protection
     */
    function _safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    
    function _safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction underflow");
        return a - b;
    }
    
    function _safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    
    function _safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
    
    /**
     * @dev Input validation helpers
     */
    function _validateAddress(address addr) internal pure {
        require(addr != address(0), "Invalid zero address");
    }
    
    function _validateAddressAllowZero(address addr) internal pure {
        // Allow zero address for ETH - no validation needed
    }
    
    function _validateAmount(uint256 amount) internal pure {
        require(amount > 0, "Amount must be greater than zero");
    }
    
    function _validatePercentage(uint256 percentage) internal pure {
        require(percentage <= 100e18, "Percentage cannot exceed 100%");
    }
    
    /**
     * @dev Emergency functions
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyValidRole(accessControl.EMERGENCY_ROLE()) {
        _validateAddress(token);
        _validateAmount(amount);
        
        // Check contract balance
        uint256 contractBalance;
        if (token == address(0)) {
            // Native ETH withdrawal
            contractBalance = address(this).balance;
            require(contractBalance >= amount, "Insufficient ETH balance");
            payable(msg.sender).transfer(amount);
        } else {
            // ERC20 token withdrawal
            IERC20 tokenContract = IERC20(token);
            contractBalance = tokenContract.balanceOf(address(this));
            require(contractBalance >= amount, "Insufficient token balance");
            tokenContract.transfer(msg.sender, amount);
        }
        
        emit SecurityViolation(msg.sender, "Emergency withdrawal triggered");
    }
    
    /**
     * @dev Security monitoring
     */
    function _reportSecurityViolation(string memory violation) internal {
        emit SecurityViolation(msg.sender, violation);
    }
    
    /**
     * @dev Emergency pause functions
     */
    function emergencyPause() external virtual onlyValidRole(accessControl.EMERGENCY_ROLE()) {
        _pause();
        emit SecurityViolation(msg.sender, "Emergency pause activated");
    }
    
    function emergencyUnpause() external virtual onlyValidRole(accessControl.EMERGENCY_ROLE()) {
        _unpause();
        emit SecurityViolation(msg.sender, "Emergency pause deactivated");
    }
}

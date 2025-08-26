// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AccessControlManager
 * @dev Centralized access control and emergency management for Fluid Protocol
 */
contract AccessControlManager is AccessControl, Pausable, ReentrancyGuard {
    
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    // Emergency controls
    mapping(address => bool) public contractPaused;
    mapping(address => uint256) public lastEmergencyAction;
    
    // Rate limiting
    mapping(address => mapping(bytes4 => uint256)) public lastFunctionCall;
    mapping(bytes4 => uint256) public functionCooldown;
    
    // Fee management
    address public feeRecipient;
    
    // Events
    event EmergencyPause(address indexed contract_, address indexed caller);
    event EmergencyUnpause(address indexed contract_, address indexed caller);
    event RoleGrantedWithExpiry(bytes32 indexed role, address indexed account, uint256 expiry);
    event FunctionRateLimited(address indexed caller, bytes4 indexed selector);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        
        // Set default fee recipient to deployer
        feeRecipient = msg.sender;
        
        // Set default cooldowns (in seconds)
        functionCooldown[bytes4(keccak256("liquidate(address,address)"))] = 1; // 1 second
        functionCooldown[bytes4(keccak256("updatePrice(address,uint256)"))] = 60; // 1 minute
        functionCooldown[bytes4(keccak256("setRiskParameters(address,tuple)"))] = 3600; // 1 hour
    }
    
    /**
     * @dev Enhanced role management with expiry
     */
    mapping(bytes32 => mapping(address => uint256)) public roleExpiry;
    
    function grantRoleWithExpiry(
        bytes32 role,
        address account,
        uint256 expiry
    ) external onlyRole(getRoleAdmin(role)) {
        require(expiry > block.timestamp, "Expiry must be in future");
        _grantRole(role, account);
        roleExpiry[role][account] = expiry;
        emit RoleGrantedWithExpiry(role, account, expiry);
    }
    
    function hasValidRole(bytes32 role, address account) public view returns (bool) {
        if (!hasRole(role, account)) return false;
        uint256 expiry = roleExpiry[role][account];
        return expiry == 0 || expiry > block.timestamp;
    }
    
    /**
     * @dev Emergency pause system
     */
    function emergencyPause(address contract_) external onlyRole(EMERGENCY_ROLE) {
        contractPaused[contract_] = true;
        lastEmergencyAction[contract_] = block.timestamp;
        emit EmergencyPause(contract_, msg.sender);
    }
    
    function emergencyUnpause(address contract_) external onlyRole(ADMIN_ROLE) {
        require(
            block.timestamp >= lastEmergencyAction[contract_] + 1 hours,
            "Must wait 1 hour after emergency pause"
        );
        contractPaused[contract_] = false;
        emit EmergencyUnpause(contract_, msg.sender);
    }
    
    /**
     * @dev Rate limiting system
     */
    modifier rateLimited(bytes4 selector) {
        uint256 cooldown = functionCooldown[selector];
        if (cooldown > 0) {
            require(
                block.timestamp >= lastFunctionCall[msg.sender][selector] + cooldown,
                "Function call rate limited"
            );
            lastFunctionCall[msg.sender][selector] = block.timestamp;
            emit FunctionRateLimited(msg.sender, selector);
        }
        _;
    }
    
    /**
     * @dev MEV protection
     */
    mapping(address => uint256) public lastActionBlock;
    
    modifier antiMEV() {
        require(
            lastActionBlock[msg.sender] < block.number,
            "Action already performed this block"
        );
        lastActionBlock[msg.sender] = block.number;
        _;
    }
    
    /**
     * @dev Contract-specific pause checks
     */
    modifier whenContractNotPaused(address contract_) {
        require(!contractPaused[contract_], "Contract is paused");
        _;
    }
    
    /**
     * @dev Update function cooldowns
     */
    function setFunctionCooldown(
        bytes4 selector,
        uint256 cooldown
    ) external onlyRole(ADMIN_ROLE) {
        functionCooldown[selector] = cooldown;
    }
    
    /**
     * @dev Batch role operations
     */
    function batchGrantRoles(
        bytes32[] calldata roles,
        address[] calldata accounts
    ) external onlyRole(ADMIN_ROLE) {
        require(roles.length == accounts.length, "Array length mismatch");
        for (uint256 i = 0; i < roles.length; i++) {
            _grantRole(roles[i], accounts[i]);
        }
    }
    
    function batchRevokeRoles(
        bytes32[] calldata roles,
        address[] calldata accounts
    ) external onlyRole(ADMIN_ROLE) {
        require(roles.length == accounts.length, "Array length mismatch");
        for (uint256 i = 0; i < roles.length; i++) {
            _revokeRole(roles[i], accounts[i]);
        }
    }
    
    /**
     * @dev Fee recipient management
     */
    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }
    
    function setFeeRecipient(address _feeRecipient) external onlyRole(ADMIN_ROLE) {
        require(_feeRecipient != address(0), "Fee recipient cannot be zero address");
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }
}

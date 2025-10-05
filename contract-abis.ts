// Essential ABI fragments for frontend integration
export const BORROWER_OPERATIONS_ABI = [
  // Core borrowing functions
  "function openTrove(address asset, uint256 maxFeePercentage, uint256 collAmount, uint256 usdfAmount, address upperHint, address lowerHint) payable",
  "function adjustTrove(address asset, uint256 maxFeePercentage, uint256 collWithdrawal, uint256 usdfChange, bool isDebtIncrease, address upperHint, address lowerHint) payable",
  "function closeTrove(address asset)",
  "function addColl(address asset, uint256 collAmount, address upperHint, address lowerHint) payable",
  "function withdrawColl(address asset, uint256 collAmount, address upperHint, address lowerHint)",
  "function withdrawUSDF(address asset, uint256 maxFeePercentage, uint256 usdfAmount, address upperHint, address lowerHint)",
  "function repayUSDF(address asset, uint256 usdfAmount, address upperHint, address lowerHint)",
  
  // View functions
  "function getCurrentICR(address borrower, address asset) view returns (uint256)",
  "function getBorrowingFee(address asset, uint256 usdfDebt) view returns (uint256)",
  "function getCompositeDebt(address asset, uint256 debt) view returns (uint256)",
  
  // Events
  "event TroveOperationSecure(address indexed borrower, address indexed asset, uint8 operation, uint256 collChange, uint256 debtChange, uint256 gasUsed, uint256 blockNumber)"
] as const;

export const TROVE_MANAGER_ABI = [
  // Core functions
  "function liquidate(address borrower, address asset)",
  "function liquidateTroves(address asset, uint256 n)",
  "function redeemCollateral(address asset, uint256 usdfAmount, address firstRedemptionHint, address upperPartialRedemptionHint, address lowerPartialRedemptionHint, uint256 partialRedemptionHintNICR, uint256 maxIterations, uint256 maxFeePercentage)",
  
  // View functions
  "function getTroveDebtAndColl(address borrower, address asset) view returns (uint256 debt, uint256 coll)",
  "function getTroveStatus(address borrower, address asset) view returns (uint256)",
  "function getCurrentICR(address borrower, address asset) view returns (uint256)",
  "function totalDebt(address asset) view returns (uint256)",
  "function totalCollateral(address asset) view returns (uint256)",
  "function totalStakes(address asset) view returns (uint256)",
  
  // Events
  "event TroveLiquidated(address indexed borrower, address indexed asset, uint256 debt, uint256 coll, uint8 operation)",
  "event TroveUpdated(address indexed borrower, address indexed asset, uint256 debt, uint256 coll, uint256 stake, uint8 operation)",
  "event Redemption(address indexed redeemer, uint256 usdfAmount, uint256 collAmount, uint256 fee)"
] as const;

export const STABILITY_POOL_ABI = [
  // Core functions
  "function provideToSP(uint256 amount, address frontEndTag)",
  "function withdrawFromSP(uint256 amount)",
  "function withdrawAllFromSP()",
  
  // View functions
  "function getTotalUSDF() view returns (uint256)",
  "function getTotalCollateral(address asset) view returns (uint256)",
  "function getCompoundedUSDF(address depositor) view returns (uint256)",
  "function getDepositorCollateralGain(address depositor, address asset) view returns (uint256)",
  "function getDepositorFLUIDGain(address depositor) view returns (uint256)",
  "function deposits(address depositor) view returns (uint256)",
  
  // Events
  "event UserDepositChanged(address indexed depositor, uint256 newDeposit)",
  "event CollateralGainWithdrawn(address indexed depositor, address indexed asset, uint256 amount)",
  "event FLUIDPaidToDepositor(address indexed depositor, uint256 amount)",
  "event StabilityPoolUSDF(uint256 totalUSDF)",
  "event StabilityPoolCollateral(address indexed asset, uint256 totalCollateral)"
] as const;

export const PRICE_ORACLE_ABI = [
  "function getPrice(address asset) view returns (uint256)",
  "function getLastUpdateTime(address asset) view returns (uint256)",
  "function addOracle(address asset, address oracle, uint256 heartbeat)",
  
  "event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp)"
] as const;

export const USDF_ABI = [
  // ERC20 standard
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transferFrom(address from, address to, uint256 amount) returns (bool)",
  
  // Minting/Burning (for protocol contracts)
  "function mint(address to, uint256 amount)",
  "function burn(uint256 amount)",
  "function burnFrom(address from, uint256 amount)",
  
  // Events
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event Approval(address indexed owner, address indexed spender, uint256 value)"
] as const;

export const FLUID_TOKEN_ABI = [
  // ERC20 standard
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transferFrom(address from, address to, uint256 amount) returns (bool)",
  
  // Governance features
  "function delegate(address delegatee)",
  "function delegates(address account) view returns (address)",
  "function getVotes(address account) view returns (uint256)",
  "function getPastVotes(address account, uint256 timepoint) view returns (uint256)",
  
  // Events
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event Approval(address indexed owner, address indexed spender, uint256 value)",
  "event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)",
  "event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance)"
] as const;

export const ACCESS_CONTROL_ABI = [
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function getRoleAdmin(bytes32 role) view returns (bytes32)",
  "function grantRole(bytes32 role, address account)",
  "function revokeRole(bytes32 role, address account)",
  "function renounceRole(bytes32 role, address account)",
  
  // Custom roles
  "function ADMIN_ROLE() view returns (bytes32)",
  "function LIQUIDATOR_ROLE() view returns (bytes32)",
  "function EMERGENCY_ROLE() view returns (bytes32)",
  
  // Emergency functions
  "function emergencyPause(address contract)",
  "function emergencyUnpause(address contract)",
  "function contractPaused(address contract) view returns (bool)",
  
  "event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole)",
  "event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)",
  "event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)"
] as const;

// Contract addresses for easy import
export const CONTRACT_ADDRESSES = {
  borrowerOperations: "0x6C3485cbE778D340534857B93eFd569Ef43e5382",
  troveManager: "0x1e4E2d45398d7e634b0958BAEc1c151C313D22e7", 
  stabilityPool: "0xA97ceBeF1c04af1aff97C0673255A2E3317127E5",
  usdf: "0xA7297098c8294503C4228D4D06FDdEc3ADF2d8Dc",
  fluidToken: "0x1329d8C7Bf6D4F50a37c991FD494d5aE46d78089",
  priceOracle: "0x78edC46846026CA5D6053dE5730eB6800DF809Da",
  sortedTroves: "0x9af1a431d275a48Cc5dA5FD4d6E5b3ce528b157b",
  accessControl: "0xb7B6405a4B6dE57d4acb3a5067d944d94283dA22"
} as const;

// Protocol constants
export const PROTOCOL_CONSTANTS = {
  MIN_COLLATERAL_RATIO: 1.35, // 135%
  LIQUIDATION_THRESHOLD: 1.1, // 110%
  BORROWING_FEE_FLOOR: 0.005, // 0.5%
  MAX_BORROWING_FEE: 0.05, // 5%
  MIN_NET_DEBT: 200, // 200 USDF
  GAS_COMPENSATION: 200, // 200 USDF
  DECIMAL_PRECISION: 18,
  ETH_ADDRESS: "0x0000000000000000000000000000000000000000"
} as const;

// Trove status enum
export const TROVE_STATUS = {
  NON_EXISTENT: 0,
  ACTIVE: 1,
  CLOSED_BY_OWNER: 2,
  CLOSED_BY_LIQUIDATION: 3,
  CLOSED_BY_REDEMPTION: 4
} as const;

// Operation types
export const BORROWER_OPERATIONS = {
  OPEN_TROVE: 0,
  CLOSE_TROVE: 1,
  WITHDRAW_COLL: 2,
  ADD_COLL: 3,
  WITHDRAW_USDF: 4,
  REPAY_USDF: 5,
  ADJUST_TROVE: 6
} as const;
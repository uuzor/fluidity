// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IUSDF
 * @notice Interface for USDF stablecoin with mint/burn capabilities
 * @dev Extends ERC20 with controlled minting and burning
 */
interface IUSDF is IERC20 {

    // ============ Events ============

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    // ============ Errors ============

    error UnauthorizedMinter(address caller);
    error UnauthorizedBurner(address caller);
    error InvalidAmount(uint256 amount);
    error InsufficientBalance(address account, uint256 balance, uint256 required);

    // ============ Minting Functions ============

    /**
     * @notice Mint USDF tokens to an address
     * @param to The address to receive tokens
     * @param amount The amount to mint
     * @dev Only callable by authorized minters (BorrowerOperations, StabilityPool, etc.)
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Mint USDF tokens to multiple addresses in one transaction
     * @param recipients Array of addresses to receive tokens
     * @param amounts Array of amounts to mint
     * @dev Batch operation for gas efficiency
     */
    function mintBatch(address[] calldata recipients, uint256[] calldata amounts) external;

    // ============ Burning Functions ============

    /**
     * @notice Burn USDF tokens from caller's balance
     * @param amount The amount to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Burn USDF tokens from a specified address
     * @param from The address to burn from
     * @param amount The amount to burn
     * @dev Requires approval or caller must be authorized burner
     */
    function burnFrom(address from, uint256 amount) external;

    // ============ Access Control ============

    /**
     * @notice Check if address is authorized minter
     * @param account The address to check
     * @return True if authorized
     */
    function isMinter(address account) external view returns (bool);

    /**
     * @notice Check if address is authorized burner
     * @param account The address to check
     * @return True if authorized
     */
    function isBurner(address account) external view returns (bool);

    /**
     * @notice Add a minter
     * @param account The address to grant minting rights
     * @dev Only callable by admin
     */
    function addMinter(address account) external;

    /**
     * @notice Remove a minter
     * @param account The address to revoke minting rights
     * @dev Only callable by admin
     */
    function removeMinter(address account) external;

    /**
     * @notice Add a burner
     * @param account The address to grant burning rights
     * @dev Only callable by admin
     */
    function addBurner(address account) external;

    /**
     * @notice Remove a burner
     * @param account The address to revoke burning rights
     * @dev Only callable by admin
     */
    function removeBurner(address account) external;

    // ============ View Functions ============

    /**
     * @notice Get total supply of USDF
     * @return Total supply
     */
    function totalSupply() external view override returns (uint256);

    /**
     * @notice Get balance of an account
     * @param account The address to query
     * @return Balance
     */
    function balanceOf(address account) external view override returns (uint256);
}

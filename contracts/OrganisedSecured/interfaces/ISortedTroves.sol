// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ISortedTroves
 * @notice Interface for doubly linked list of Troves sorted by ICR
 * @dev Used for efficient liquidation and redemption operations
 */
interface ISortedTroves {

    // ============ Events ============

    event NodeAdded(address indexed asset, address indexed id, uint256 nicr);
    event NodeRemoved(address indexed asset, address indexed id);

    // ============ Errors ============

    error InvalidAddress();
    error NodeAlreadyExists(address id);
    error NodeDoesNotExist(address id);

    // ============ Functions ============

    /**
     * @notice Insert trove into sorted position
     * @param asset Collateral asset
     * @param id Trove owner address
     * @param nicr Nominal Individual Collateral Ratio
     * @param prevId Hint for insertion (address before)
     * @param nextId Hint for insertion (address after)
     */
    function insert(
        address asset,
        address id,
        uint256 nicr,
        address prevId,
        address nextId
    ) external;

    /**
     * @notice Remove trove from list
     * @param asset Collateral asset
     * @param id Trove owner address
     */
    function remove(address asset, address id) external;

    /**
     * @notice Reinsert trove with new NICR
     * @param asset Collateral asset
     * @param id Trove owner address
     * @param newNicr New nominal ICR
     * @param prevId Hint for insertion
     * @param nextId Hint for insertion
     */
    function reInsert(
        address asset,
        address id,
        uint256 newNicr,
        address prevId,
        address nextId
    ) external;

    /**
     * @notice Check if trove exists in list
     * @param asset Collateral asset
     * @param id Trove owner address
     */
    function contains(address asset, address id) external view returns (bool);

    /**
     * @notice Check if list is full
     * @param asset Collateral asset
     */
    function isFull(address asset) external view returns (bool);

    /**
     * @notice Check if list is empty
     * @param asset Collateral asset
     */
    function isEmpty(address asset) external view returns (bool);

    /**
     * @notice Get list size
     * @param asset Collateral asset
     */
    function getSize(address asset) external view returns (uint256);

    /**
     * @notice Get maximum list size
     */
    function getMaxSize() external view returns (uint256);

    /**
     * @notice Get first trove (highest ICR)
     * @param asset Collateral asset
     */
    function getFirst(address asset) external view returns (address);

    /**
     * @notice Get last trove (lowest ICR)
     * @param asset Collateral asset
     */
    function getLast(address asset) external view returns (address);

    /**
     * @notice Get next trove in list
     * @param asset Collateral asset
     * @param id Current trove
     */
    function getNext(address asset, address id) external view returns (address);

    /**
     * @notice Get previous trove in list
     * @param asset Collateral asset
     * @param id Current trove
     */
    function getPrev(address asset, address id) external view returns (address);

    /**
     * @notice Find valid insert position for NICR
     * @param asset Collateral asset
     * @param nicr Nominal ICR to insert
     * @param prevId Starting hint (previous)
     * @param nextId Starting hint (next)
     * @return Previous trove address
     * @return Next trove address
     */
    function findInsertPosition(
        address asset,
        uint256 nicr,
        address prevId,
        address nextId
    ) external view returns (address, address);

    /**
     * @notice Validate insert position
     * @param asset Collateral asset
     * @param nicr Nominal ICR
     * @param prevId Previous trove
     * @param nextId Next trove
     */
    function validInsertPosition(
        address asset,
        uint256 nicr,
        address prevId,
        address nextId
    ) external view returns (bool);
}

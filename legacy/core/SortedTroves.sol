// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SortedTroves
 * @dev Efficient doubly-linked list for maintaining troves sorted by their nominal ICR
 * Critical for gas-efficient liquidation operations in the Fluid Protocol
 */
contract SortedTroves is Ownable, ReentrancyGuard {
    
    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;
    
    // Structs
    struct Node {
        bool exists;
        address nextId;                  // Id of next node (with higher NICR) in the list
        address prevId;                  // Id of previous node (with lower NICR) in the list
    }
    
    // State variables
    mapping(address => mapping(address => Node)) public data; // asset => borrower => Node
    mapping(address => address) public head; // asset => head of list (highest NICR)
    mapping(address => address) public tail; // asset => tail of list (lowest NICR)
    mapping(address => uint256) public size; // asset => number of nodes in list
    mapping(address => uint256) public maxSize; // asset => maximum allowed size
    
    // Authorized contracts
    mapping(address => bool) public isTroveManager;
    mapping(address => bool) public isBorrowerOperations;
    
    // Events
    event NodeAdded(address indexed asset, address indexed id, uint256 NICR);
    event NodeRemoved(address indexed asset, address indexed id);
    event TroveManagerAddressChanged(address indexed newAddress);
    event BorrowerOperationsAddressChanged(address indexed newAddress);
    
    modifier onlyTroveManager() {
        require(isTroveManager[msg.sender], "SortedTroves: Caller is not TroveManager");
        _;
    }
    
    modifier onlyBorrowerOperations() {
        require(isBorrowerOperations[msg.sender], "SortedTroves: Caller is not BorrowerOperations");
        _;
    }
    
    modifier onlyTroveManagerOrBorrowerOperations() {
        require(
            isTroveManager[msg.sender] || isBorrowerOperations[msg.sender],
            "SortedTroves: Caller is not authorized"
        );
        _;
    }
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Set authorized TroveManager contract
     */
    function setTroveManager(address _troveManager) external onlyOwner {
        require(_troveManager != address(0), "Invalid address");
        isTroveManager[_troveManager] = true;
        emit TroveManagerAddressChanged(_troveManager);
    }
    
    /**
     * @dev Set authorized BorrowerOperations contract
     */
    function setBorrowerOperations(address _borrowerOperations) external onlyOwner {
        require(_borrowerOperations != address(0), "Invalid address");
        isBorrowerOperations[_borrowerOperations] = true;
        emit BorrowerOperationsAddressChanged(_borrowerOperations);
    }
    
    /**
     * @dev Set maximum size for a specific asset's list
     */
    function setMaxSize(address asset, uint256 _maxSize) external onlyOwner {
        maxSize[asset] = _maxSize;
    }
    
    /**
     * @dev Insert a trove into the sorted list
     */
    function insert(
        address asset,
        address id,
        uint256 NICR,
        address prevId,
        address nextId
    ) external onlyTroveManagerOrBorrowerOperations {
        require(id != address(0), "SortedTroves: Id cannot be zero");
        require(!contains(asset, id), "SortedTroves: List already contains the node");
        require(size[asset] < maxSize[asset], "SortedTroves: List is full");
        
        address prevId_final = prevId;
        address nextId_final = nextId;
        
        if (!_validInsertPosition(asset, NICR, prevId, nextId)) {
            // Find the correct insert position
            (prevId_final, nextId_final) = _findInsertPosition(asset, NICR, prevId, nextId);
        }
        
        data[asset][id].exists = true;
        
        if (prevId_final == address(0) && nextId_final == address(0)) {
            // Insert as the only node
            head[asset] = id;
            tail[asset] = id;
        } else if (prevId_final == address(0)) {
            // Insert at head
            data[asset][id].nextId = head[asset];
            data[asset][head[asset]].prevId = id;
            head[asset] = id;
        } else if (nextId_final == address(0)) {
            // Insert at tail
            data[asset][id].prevId = tail[asset];
            data[asset][tail[asset]].nextId = id;
            tail[asset] = id;
        } else {
            // Insert in middle
            data[asset][id].nextId = nextId_final;
            data[asset][id].prevId = prevId_final;
            data[asset][prevId_final].nextId = id;
            data[asset][nextId_final].prevId = id;
        }
        
        size[asset]++;
        emit NodeAdded(asset, id, NICR);
    }
    
    /**
     * @dev Remove a trove from the sorted list
     */
    function remove(address asset, address id) external onlyTroveManagerOrBorrowerOperations {
        require(contains(asset, id), "SortedTroves: List does not contain the id");
        
        if (size[asset] > 1) {
            // List contains more than a single node
            if (id == head[asset]) {
                // Remove head
                head[asset] = data[asset][id].nextId;
                data[asset][head[asset]].prevId = address(0);
            } else if (id == tail[asset]) {
                // Remove tail
                tail[asset] = data[asset][id].prevId;
                data[asset][tail[asset]].nextId = address(0);
            } else {
                // Remove middle node
                data[asset][data[asset][id].nextId].prevId = data[asset][id].prevId;
                data[asset][data[asset][id].prevId].nextId = data[asset][id].nextId;
            }
        } else {
            // List contains a single node
            head[asset] = address(0);
            tail[asset] = address(0);
        }
        
        delete data[asset][id];
        size[asset]--;
        
        emit NodeRemoved(asset, id);
    }
    
    /**
     * @dev Re-insert a trove to maintain sorted order (used when NICR changes)
     */
    function reInsert(
        address asset,
        address id,
        uint256 newNICR,
        address prevId,
        address nextId
    ) external onlyTroveManagerOrBorrowerOperations {
        require(contains(asset, id), "SortedTroves: List does not contain the id");
        
        // Remove the node
        this.remove(asset, id);
        
        // Re-insert with new NICR
        this.insert(asset, id, newNICR, prevId, nextId);
    }
    
    /**
     * @dev Check if the list contains a specific trove
     */
    function contains(address asset, address id) public view returns (bool) {
        return data[asset][id].exists;
    }
    
    /**
     * @dev Check if the list is empty
     */
    function isEmpty(address asset) external view returns (bool) {
        return size[asset] == 0;
    }
    
    /**
     * @dev Get the size of the list for an asset
     */
    function getSize(address asset) external view returns (uint256) {
        return size[asset];
    }
    
    /**
     * @dev Get the maximum size allowed for an asset
     */
    function getMaxSize(address asset) external view returns (uint256) {
        return maxSize[asset];
    }
    
    /**
     * @dev Get the first (highest NICR) trove in the list
     */
    function getFirst(address asset) external view returns (address) {
        return head[asset];
    }
    
    /**
     * @dev Get the last (lowest NICR) trove in the list
     */
    function getLast(address asset) external view returns (address) {
        return tail[asset];
    }
    
    /**
     * @dev Get the next trove in the list
     */
    function getNext(address asset, address id) external view returns (address) {
        return data[asset][id].nextId;
    }
    
    /**
     * @dev Get the previous trove in the list
     */
    function getPrev(address asset, address id) external view returns (address) {
        return data[asset][id].prevId;
    }
    
    /**
     * @dev Find the correct insert position for a given NICR
     */
    function findInsertPosition(
        address asset,
        uint256 NICR,
        address prevId,
        address nextId
    ) external view returns (address, address) {
        return _findInsertPosition(asset, NICR, prevId, nextId);
    }
    
    /**
     * @dev Validate that the provided hints are correct for insertion
     */
    function validInsertPosition(
        address asset,
        uint256 NICR,
        address prevId,
        address nextId
    ) external view returns (bool) {
        return _validInsertPosition(asset, NICR, prevId, nextId);
    }
    
    // Internal functions
    function _validInsertPosition(
        address asset,
        uint256 NICR,
        address prevId,
        address nextId
    ) internal view returns (bool) {
        if (prevId == address(0) && nextId == address(0)) {
            // Empty list
            return size[asset] == 0;
        } else if (prevId == address(0)) {
            // Insert at head
            return data[asset][nextId].exists && 
                   NICR >= _getTroveNICR(asset, nextId) && 
                   nextId == head[asset];
        } else if (nextId == address(0)) {
            // Insert at tail
            return data[asset][prevId].exists && 
                   NICR <= _getTroveNICR(asset, prevId) && 
                   prevId == tail[asset];
        } else {
            // Insert in middle
            return data[asset][prevId].exists && 
                   data[asset][nextId].exists && 
                   NICR <= _getTroveNICR(asset, prevId) && 
                   NICR >= _getTroveNICR(asset, nextId) &&
                   data[asset][prevId].nextId == nextId;
        }
    }
    
    function _findInsertPosition(
        address asset,
        uint256 NICR,
        address prevId,
        address nextId
    ) internal view returns (address, address) {
        address prevId_final = prevId;
        address nextId_final = nextId;
        
        if (prevId_final != address(0)) {
            if (!contains(asset, prevId_final) || NICR > _getTroveNICR(asset, prevId_final)) {
                // prevId does not exist anymore or now has a smaller NICR than the given NICR
                prevId_final = address(0);
            }
        }
        
        if (nextId_final != address(0)) {
            if (!contains(asset, nextId_final) || NICR < _getTroveNICR(asset, nextId_final)) {
                // nextId does not exist anymore or now has a larger NICR than the given NICR
                nextId_final = address(0);
            }
        }
        
        if (prevId_final == address(0) && nextId_final == address(0)) {
            // No hint - descend list starting from head
            return _descendList(asset, NICR, head[asset]);
        } else if (prevId_final == address(0)) {
            // No prevId hint - ascend list starting from nextId
            return _ascendList(asset, NICR, nextId_final);
        } else if (nextId_final == address(0)) {
            // No nextId hint - descend list starting from prevId
            return _descendList(asset, NICR, prevId_final);
        } else {
            // Both hints provided
            return _descendList(asset, NICR, prevId_final);
        }
    }
    
    function _descendList(
        address asset,
        uint256 NICR,
        address startId
    ) internal view returns (address, address) {
        // If startId is the head, check if the insert position is before the head
        if (data[asset][startId].prevId == address(0) && NICR >= _getTroveNICR(asset, startId)) {
            return (address(0), startId);
        }
        
        address prevId = startId;
        address nextId = data[asset][startId].nextId;
        
        // Descend the list until we reach the end or until we find a valid insert position
        while (prevId != address(0) && !_validInsertPosition(asset, NICR, prevId, nextId)) {
            prevId = data[asset][prevId].nextId;
            nextId = data[asset][prevId].nextId;
        }
        
        return (prevId, nextId);
    }
    
    function _ascendList(
        address asset,
        uint256 NICR,
        address startId
    ) internal view returns (address, address) {
        // If startId is the tail, check if the insert position is after the tail
        if (data[asset][startId].nextId == address(0) && NICR <= _getTroveNICR(asset, startId)) {
            return (startId, address(0));
        }
        
        address nextId = startId;
        address prevId = data[asset][startId].prevId;
        
        // Ascend the list until we reach the end or until we find a valid insert position
        while (nextId != address(0) && !_validInsertPosition(asset, NICR, prevId, nextId)) {
            nextId = data[asset][nextId].prevId;
            prevId = data[asset][nextId].prevId;
        }
        
        return (prevId, nextId);
    }
    
    function _getTroveNICR(address asset, address trove) internal view returns (uint256) {
        // This would call the TroveManager to get the NICR
        // For now, return a placeholder - this will be integrated with TroveManager
        return DECIMAL_PRECISION;
    }
    
    /**
     * @dev Get all troves in the list (for debugging/testing purposes)
     * WARNING: This can be gas-expensive for large lists
     */
    function getAllTroves(address asset) external view returns (address[] memory) {
        address[] memory troves = new address[](size[asset]);
        address currentId = head[asset];
        
        for (uint256 i = 0; i < size[asset]; i++) {
            troves[i] = currentId;
            currentId = data[asset][currentId].nextId;
        }
        
        return troves;
    }
}

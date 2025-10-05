// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/PackedTrove.sol";
import "../libraries/TransientStorage.sol";
import "../libraries/BatchOperations.sol";
import "../libraries/CalldataDecoder.sol";
import "../libraries/GasOptimizedMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PackedTroveTest
 * @notice Test contract for PackedTrove library
 */
contract PackedTroveTest {
    using PackedTrove for uint256;

    function testPack(
        uint128 debt,
        uint256 collateral,
        uint32 lastUpdate,
        uint8 status,
        uint8 assetId
    ) external pure returns (uint256) {
        return PackedTrove.pack(debt, collateral, lastUpdate, status, assetId);
    }

    function testUnpack(uint256 packed) external pure returns (PackedTrove.Trove memory) {
        return PackedTrove.unpack(packed);
    }

    function testGetDebt(uint256 packed) external pure returns (uint128) {
        return PackedTrove.getDebt(packed);
    }

    function testGetCollateral(uint256 packed) external pure returns (uint256) {
        return PackedTrove.getCollateral(packed);
    }

    function testGetStatus(uint256 packed) external pure returns (uint8) {
        return PackedTrove.getStatus(packed);
    }

    function testGetTimestamp(uint256 packed) external pure returns (uint32) {
        return PackedTrove.getTimestamp(packed);
    }

    function testSetDebt(uint256 packed, uint128 newDebt) external pure returns (uint256) {
        return PackedTrove.setDebt(packed, newDebt);
    }

    function testCreate(
        uint128 debt,
        uint256 collateral,
        uint8 assetId
    ) external view returns (uint256) {
        return PackedTrove.create(debt, collateral, assetId);
    }
}

/**
 * @title TransientStorageTest
 * @notice Test contract for TransientStorage library
 */
contract TransientStorageTest is TransientReentrancyGuard {
    using TransientStorage for bytes32;

    bytes32 constant TEST_SLOT = keccak256("test.slot");

    function testTstore(uint256 value) external {
        TEST_SLOT.tstore(value);
    }

    function testTload() external view returns (uint256) {
        return TEST_SLOT.tload();
    }

    function testNonReentrant() external nonReentrant returns (uint256) {
        return 42;
    }

    function testReentrantCall() external nonReentrant {
        // This function has the nonReentrant modifier
        // If we try to call another nonReentrant function, it should revert
        this.testNonReentrantHelper();
    }

    function testNonReentrantHelper() external nonReentrant returns (uint256) {
        // This will fail if called from testReentrantCall because both have nonReentrant
        return 99;
    }
}

/**
 * @title MockERC20Mintable
 * @notice Mock ERC20 token with mint/burn functionality for testing
 */
contract MockERC20Mintable is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}

/**
 * @title BatchOperationsTest
 * @notice Test contract for BatchOperations library
 */
contract BatchOperationsTest {
    using BatchOperations for address;

    function testBatchMint(
        address token,
        address[] memory recipients,
        uint256[] memory amounts
    ) external {
        BatchOperations.batchMint(token, recipients, amounts);
    }

    function testBatchBurnFrom(
        address token,
        address[] memory holders,
        uint256[] memory amounts
    ) external {
        BatchOperations.batchBurnFrom(token, holders, amounts);
    }

    function testBatchTransferFrom(
        address token,
        address from,
        address[] memory recipients,
        uint256[] memory amounts
    ) external {
        BatchOperations.batchTransferFrom(token, from, recipients, amounts);
    }

    function testMakeArrays3(
        address addr1,
        address addr2,
        address addr3,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) external pure returns (address[] memory, uint256[] memory) {
        return BatchOperations.makeArrays3(addr1, addr2, addr3, amount1, amount2, amount3);
    }

    function testMakeArrays2(
        address addr1,
        address addr2,
        uint256 amount1,
        uint256 amount2
    ) external pure returns (address[] memory, uint256[] memory) {
        return BatchOperations.makeArrays2(addr1, addr2, amount1, amount2);
    }

    function testMint3(
        address token,
        address recipient1,
        address recipient2,
        address recipient3,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) external {
        BatchOperations.mint3(token, recipient1, recipient2, recipient3, amount1, amount2, amount3);
    }

    function testBurn2From(
        address token,
        address holder1,
        address holder2,
        uint256 amount1,
        uint256 amount2
    ) external {
        BatchOperations.burn2From(token, holder1, holder2, amount1, amount2);
    }
}

/**
 * @title CalldataDecoderTest
 * @notice Test contract for CalldataDecoder library
 */
contract CalldataDecoderTest {
    using CalldataDecoder for bytes32;

    function testEncodeOpenTrove(
        uint16 maxFeePercentage,
        uint256 collAmount,
        uint256 usdfAmount,
        uint80 hintsEncoded
    ) external pure returns (bytes32) {
        return CalldataDecoder.encodeOpenTrove(maxFeePercentage, collAmount, usdfAmount, hintsEncoded);
    }

    function testDecodeOpenTrove(bytes32 packed)
        external
        pure
        returns (uint16, uint256, uint256, uint80)
    {
        return CalldataDecoder.decodeOpenTrove(packed);
    }

    function testEncodeAdjustTrove(
        uint16 maxFeePercentage,
        uint256 collChange,
        uint256 usdfChange,
        bool isCollIncrease,
        bool isDebtIncrease,
        uint64 hintsEncoded
    ) external pure returns (bytes32) {
        return CalldataDecoder.encodeAdjustTrove(
            maxFeePercentage,
            collChange,
            usdfChange,
            isCollIncrease,
            isDebtIncrease,
            hintsEncoded
        );
    }

    function testDecodeAdjustTrove(bytes32 packed)
        external
        pure
        returns (uint16, uint256, uint256, bool, bool, uint64)
    {
        return CalldataDecoder.decodeAdjustTrove(packed);
    }

    function testPackHints(address upper, address lower) external pure returns (uint160) {
        return CalldataDecoder.packHints(upper, lower);
    }

    function testUnpackHints(uint160 packed) external pure returns (address, address) {
        return CalldataDecoder.unpackHints(packed);
    }

    function testPercentageToBasisPoints(uint256 percentage) external pure returns (uint16) {
        return CalldataDecoder.percentageToBasisPoints(percentage);
    }

    function testBasisPointsToPercentage(uint16 basisPoints) external pure returns (uint256) {
        return CalldataDecoder.basisPointsToPercentage(basisPoints);
    }
}

/**
 * @title GasOptimizedMathTest
 * @notice Test contract for GasOptimizedMath library
 */
contract GasOptimizedMathTest {
    using GasOptimizedMath for uint256;

    function testMulDiv(uint256 x, uint256 y, uint256 denominator) external pure returns (uint256) {
        return GasOptimizedMath.mulDiv(x, y, denominator);
    }

    function testSqrt(uint256 x) external pure returns (uint256) {
        return GasOptimizedMath.sqrt(x);
    }

    function testMin(uint256 a, uint256 b) external pure returns (uint256) {
        return GasOptimizedMath.min(a, b);
    }

    function testMax(uint256 a, uint256 b) external pure returns (uint256) {
        return GasOptimizedMath.max(a, b);
    }

    function testAbs(uint256 a, uint256 b) external pure returns (uint256) {
        return GasOptimizedMath.abs(a, b);
    }

    function testPercentMul(uint256 value, uint256 percentage) external pure returns (uint256) {
        return GasOptimizedMath.percentMul(value, percentage);
    }

    function testPercentDiv(uint256 value, uint256 percentage) external pure returns (uint256) {
        return GasOptimizedMath.percentDiv(value, percentage);
    }

    function testAverage(uint256 a, uint256 b) external pure returns (uint256) {
        return GasOptimizedMath.average(a, b);
    }

    function testMul(uint256 a, uint256 b) external pure returns (uint256) {
        return GasOptimizedMath.mul(a, b);
    }

    function testAdd(uint256 a, uint256 b) external pure returns (uint256) {
        return GasOptimizedMath.add(a, b);
    }

    function testSub(uint256 a, uint256 b) external pure returns (uint256) {
        return GasOptimizedMath.sub(a, b);
    }

    function testMulDivUp(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256) {
        return GasOptimizedMath.mulDivUp(a, b, denominator);
    }

    function testBasisPoints(uint256 value, uint256 bps) external pure returns (uint256) {
        return GasOptimizedMath.basisPoints(value, bps);
    }
}

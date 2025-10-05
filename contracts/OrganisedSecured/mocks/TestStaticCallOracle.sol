// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract TestStaticCallOracle {
    address public immutable priceOracle;

    constructor(address _priceOracle) {
        priceOracle = _priceOracle;
    }

    function testGetPrice(address asset) external view returns (uint256 price) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getPrice(address)", asset)
        );
        require(success, "Staticcall failed");
        price = abi.decode(data, (uint256));
    }

    function testGetPriceWithTryCatch(address asset) external view returns (bool success, uint256 price, bytes memory errorData) {
        bytes memory data;
        (success, data) = priceOracle.staticcall(
            abi.encodeWithSignature("getPrice(address)", asset)
        );

        if (success && data.length >= 32) {
            price = abi.decode(data, (uint256));
        } else {
            errorData = data;
        }
    }
}

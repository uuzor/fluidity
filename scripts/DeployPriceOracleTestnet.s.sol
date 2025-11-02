// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/OrganisedSecured/core/PriceOracle.sol";
import "../contracts/OrganisedSecured/utils/AccessControlManager.sol";

/**
 * @title DeployPriceOracleTestnet
 * @notice Deployment script for PriceOracle on Unicorn Ultra Nebulas testnet
 */
contract DeployPriceOracleTestnet is Script {
    // Unicorn Ultra Nebulas testnet Orochi address
    address constant OROCHI_ORACLE = 0x70523434ee6a9870410960E2615406f8F9850676;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying on Unicorn Ultra Nebulas testnet...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Orochi Oracle:", OROCHI_ORACLE);
        
        // Deploy AccessControlManager
        AccessControlManager accessControl = new AccessControlManager();
        console.log("AccessControlManager deployed at:", address(accessControl));
        
        // Deploy PriceOracle with Orochi integration
        PriceOracle priceOracle = new PriceOracle(address(accessControl), OROCHI_ORACLE);
        console.log("PriceOracle deployed at:", address(priceOracle));
        
        // Grant admin role to deployer
        accessControl.grantRole(accessControl.ADMIN_ROLE(), vm.addr(deployerPrivateKey));
        console.log("Admin role granted to deployer");
        
        // Register some test assets with Orochi symbols
        registerTestAssets(priceOracle);
        
        vm.stopBroadcast();
        
        console.log("\nDeployment completed!");
        console.log("PriceOracle:", address(priceOracle));
        console.log("AccessControl:", address(accessControl));
    }
    
    function registerTestAssets(PriceOracle priceOracle) internal {
        console.log("\nRegistering test assets...");
        
        // Mock Chainlink feeds (replace with real testnet feeds if available)
        address mockBTCFeed = 0x1111111111111111111111111111111111111111;
        address mockETHFeed = 0x2222222222222222222222222222222222222222;
        
        // Test asset addresses
        address btcAsset = 0x3333333333333333333333333333333333333333;
        address ethAsset = address(0); // Native ETH
        
        try priceOracle.registerOracleWithSymbol(
            btcAsset,
            mockBTCFeed,
            3600, // 1 hour heartbeat
            bytes20("BTC")
        ) {
            console.log("BTC oracle registered");
        } catch {
            console.log("BTC oracle registration failed (expected without real feed)");
        }
        
        try priceOracle.registerOracleWithSymbol(
            ethAsset,
            mockETHFeed,
            3600,
            bytes20("ETH")
        ) {
            console.log("ETH oracle registered");
        } catch {
            console.log("ETH oracle registration failed (expected without real feed)");
        }
        
        // Test Orochi direct call
        testOrochiConnection();
    }
    
    function testOrochiConnection() internal {
        console.log("\nTesting Orochi connection...");
        
        IOrocleAggregatorV2 orochi = IOrocleAggregatorV2(OROCHI_ORACLE);
        
        // Test BTC price fetch
        try orochi.getLatestData(1, bytes20("BTC")) returns (bytes memory data) {
            if (data.length >= 32) {
                uint256 btcPrice = abi.decode(data, (uint256));
                console.log("Orochi BTC price:", btcPrice);
            } else {
                console.log("Orochi returned empty data for BTC");
            }
        } catch Error(string memory reason) {
            console.log("Orochi BTC fetch failed:", reason);
        } catch {
            console.log("Orochi BTC fetch failed with unknown error");
        }
        
        // Test ETH price fetch
        try orochi.getLatestData(1, bytes20("ETH")) returns (bytes memory data) {
            if (data.length >= 32) {
                uint256 ethPrice = abi.decode(data, (uint256));
                console.log("Orochi ETH price:", ethPrice);
            } else {
                console.log("Orochi returned empty data for ETH");
            }
        } catch Error(string memory reason) {
            console.log("Orochi ETH fetch failed:", reason);
        } catch {
            console.log("Orochi ETH fetch failed with unknown error");
        }
    }
}
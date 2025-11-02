#!/bin/bash

# Unicorn Ultra Nebulas testnet configuration
TESTNET_RPC="https://rpc-nebulas-testnet.uniultra.xyz"
CHAIN_ID=2484

echo "Running PriceOracle tests on Unicorn Ultra Nebulas testnet..."
echo "RPC: $TESTNET_RPC"
echo "Chain ID: $CHAIN_ID"

# Run deployment script
echo "Deploying PriceOracle..."
forge script scripts/DeployPriceOracleTestnet.s.sol:DeployPriceOracleTestnet \
    --rpc-url $TESTNET_RPC \
    --broadcast \
    --verify \
    -vvvv

# Run tests
echo "Running tests..."
forge test --match-contract PriceOracleTestnet \
    --rpc-url $TESTNET_RPC \
    --fork-url $TESTNET_RPC \
    -vvvv

echo "Tests completed!"